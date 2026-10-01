"""Acceso a Supabase con JWT por petición: conserva las políticas RLS."""

from uuid import UUID

import httpx

from app.core.config import Settings
from app.core.errors import ServiceError


class SupabaseGateway:
    def __init__(self, client: httpx.AsyncClient, settings: Settings, access_token: str):
        if not settings.SUPABASE_URL or not settings.SUPABASE_PUBLISHABLE_KEY:
            raise ServiceError(503, "Supabase no está configurado")
        self.client = client
        self.base_url = settings.SUPABASE_URL.rstrip("/")
        self.headers = {
            "apikey": settings.SUPABASE_PUBLISHABLE_KEY.get_secret_value(),
            "Authorization": f"Bearer {access_token}",
        }

    async def request(self, method: str, path: str, params: dict | None = None, data: dict | None = None):
        try:
            response = await self.client.request(
                method, f"{self.base_url}/{path}", headers=self.headers, params=params, json=data,
            )
        except httpx.TimeoutException as error:
            raise ServiceError(504, "Supabase no respondió a tiempo") from error
        except httpx.RequestError as error:
            raise ServiceError(502, "No se pudo conectar con Supabase") from error
        if response.status_code == 401:
            raise ServiceError(401, "Sesión inválida o vencida")
        if response.status_code == 403:
            raise ServiceError(403, "No tienes permisos para esta operación")
        if response.status_code == 429:
            raise ServiceError(429, "Demasiadas solicitudes. Inténtalo de nuevo más tarde")
        if response.status_code == 400:
            raise ServiceError(400, "Operación no válida. Revisa el rol, la empresa y que permanezca un administrador activo")
        if response.is_error:
            raise ServiceError(502, "No se pudo consultar Supabase; revisa la configuración y las migraciones")
        if response.status_code == 204 or not response.content:
            return None
        try:
            return response.json()
        except ValueError as error:
            raise ServiceError(502, "Supabase devolvió una respuesta inválida") from error

    async def get(self, path: str, params: dict | None = None):
        return await self.request("GET", path, params=params)

    async def verified_user_id(self) -> str:
        user = await self.get("auth/v1/user")
        try:
            user_id = str(UUID(user["id"]))
        except (ValueError, TypeError, KeyError) as error:
            raise ServiceError(401, "Sesión inválida") from error
        if user.get("is_anonymous"):
            raise ServiceError(403, "Se requiere una cuenta identificada")
        return user_id

    async def authenticated_identity(self) -> tuple[str, frozenset[str]]:
        user_id = await self.verified_user_id()
        profile = await self.rows("profiles", {"select": "id,is_active", "id": f"eq.{user_id}", "limit": 1})
        if not profile or profile[0].get("is_active") is not True:
            raise ServiceError(403, "El perfil no está activo")
        assignments = await self.rows("user_roles", {
            "select": "role", "user_id": f"eq.{user_id}", "revoked_at": "is.null",
        })
        roles = frozenset(row["role"] for row in assignments)
        return user_id, roles

    async def rows(self, table: str, params: dict) -> list[dict]:
        data = await self.get(f"rest/v1/{table}", params)
        if not isinstance(data, list) or any(not isinstance(row, dict) for row in data):
            raise ServiceError(502, "Supabase devolvió una respuesta inválida")
        return data
