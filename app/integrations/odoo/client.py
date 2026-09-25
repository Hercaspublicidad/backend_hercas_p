import httpx

from app.core.config import Settings
from app.core.errors import ServiceError


class OdooClient:
    def __init__(self, client: httpx.AsyncClient, settings: Settings):
        self.client = client
        self.settings = settings

    async def call(self, model: str, method: str, data: dict | None = None):
        if not self.settings.ODOO_URL or not self.settings.ODOO_API_KEY:
            raise ServiceError(503, "Odoo no está configurado")
        headers = {
            "Authorization": f"bearer {self.settings.ODOO_API_KEY.get_secret_value()}",
            "Content-Type": "application/json", "User-Agent": "Hercas-Sistema-Externos/1.0",
        }
        if self.settings.ODOO_DATABASE:
            headers["X-Odoo-Database"] = self.settings.ODOO_DATABASE
        try:
            response = await self.client.post(
                f"{self.settings.ODOO_URL.rstrip('/')}/json/2/{model}/{method}",
                headers=headers, json=data or {},
            )
            response.raise_for_status()
            result = response.json()
            if not isinstance(result, list):
                raise ValueError("Respuesta inesperada")
            return result
        except httpx.TimeoutException as error:
            raise ServiceError(504, "Odoo no respondió a tiempo") from error
        except (httpx.HTTPError, ValueError) as error:
            raise ServiceError(502, "No se pudo consultar Odoo") from error
