"""Identidad compartida por todos los módulos de la plataforma."""

from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
import httpx
from app.core.auth import require_roles
from app.core.errors import ServiceError
from uuid import UUID

from app.core.auth import DatabaseDependency, SessionDependency

router = APIRouter(prefix="/auth", tags=["Autenticación"])


class AccessUpdate(BaseModel):
    roles: list[str] = Field(max_length=10)
    active: bool


class InvitationInput(BaseModel):
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
    role: str = Field(min_length=1, max_length=60)
    customer_account_id: UUID | None = None


@router.get("/administracion")
async def administration(session: SessionDependency, offset: int = Query(0, ge=0)):
    require_roles(session, "systems_admin")
    db = session.database
    users = await db.request("POST", "rest/v1/rpc/admin_user_directory", data={"page_offset": offset})
    # Scope grants to this page, avoiding PostgREST row-cap truncation across all users.
    user_ids = ",".join(str(UUID(user["id"])) for user in users)
    return {
        "users": users,
        "assignments": await db.rows("user_roles", {"select": "user_id,role", "user_id": f"in.({user_ids})", "revoked_at": "is.null"}) if user_ids else [],
        "roles": await db.rows("roles", {"select": "code,name,scope", "order": "name.asc"}),
        "permissions": await db.rows("role_permissions", {"select": "role,permission"}),
        "invitations": await db.rows("invitations", {"select": "id,email,role,expires_at,accepted_at,revoked_at", "order": "created_at.desc", "limit": 100}),
        "customers": await db.rows("customer_accounts", {"select": "id,name", "is_active": "eq.true", "order": "name.asc", "limit": 100}),
    }


@router.post("/usuarios/{user_id}/acceso")
async def update_access(user_id: UUID, body: AccessUpdate, session: SessionDependency):
    require_roles(session, "systems_admin")
    await session.database.request("POST", "rest/v1/rpc/admin_update_access", data={"target_user": str(user_id), "new_roles": body.roles, "active": body.active})
    return {"updated": True}


@router.post("/invitaciones")
async def create_invitation(body: InvitationInput, session: SessionDependency):
    require_roles(session, "systems_admin")
    result = await session.database.request("POST", "rest/v1/rpc/admin_create_invitation", data={
        "invite_email": body.email, "invite_role": body.role,
        "account_id": str(body.customer_account_id) if body.customer_account_id else None,
    })
    return {"invitationId": result}


@router.post("/invitaciones/{invitation_id}/revocar")
async def revoke_invitation(invitation_id: UUID, session: SessionDependency):
    require_roles(session, "systems_admin")
    await session.database.request("POST", "rest/v1/rpc/admin_revoke_invitation", data={"invitation_id": str(invitation_id)})
    return {"revoked": True}


@router.post("/invitaciones/{invitation_id}/enviar")
async def send_invitation(invitation_id: UUID, session: SessionDependency, request: Request):
    require_roles(session, "systems_admin")
    settings = request.app.state.settings
    if not settings.SUPABASE_SECRET_KEY:
        raise ServiceError(503, "Falta configurar el envío de invitaciones en el servidor")
    from datetime import datetime, timezone
    rows = await session.database.rows("invitations", {"select": "email", "id": f"eq.{invitation_id}", "accepted_at": "is.null", "revoked_at": "is.null", "expires_at": f"gt.{datetime.now(timezone.utc).isoformat()}", "limit": 1})
    if not rows:
        raise ServiceError(404, "Invitación no disponible")
    key = settings.SUPABASE_SECRET_KEY.get_secret_value()
    try:
        response = await request.app.state.http.post(
            f"{settings.SUPABASE_URL.rstrip('/')}/auth/v1/invite",
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
            params={"redirect_to": f"{settings.AUTH_SITE_URL.rstrip('/')}/auth/confirmar?invitation={invitation_id}"},
            json={"email": rows[0]["email"]},
        )
    except httpx.RequestError as error:
        raise ServiceError(502, "No se pudo enviar la invitación; puedes reintentar") from error
    if response.is_error:
        raise ServiceError(502, "No se pudo enviar. Revisa SMTP, límites de Auth y si el correo ya tiene cuenta")
    return {"sent": True}


@router.get("/sesion")
async def session_info(session: SessionDependency):
    # Autenticación no implica acceso a un módulo de negocio.
    return {"userId": session.user_id, "roles": sorted(session.roles)}


@router.post("/invitaciones/{invitation_id}/aceptar")
async def accept_invitation(invitation_id: UUID, database: DatabaseDependency):
    """La primera aceptación necesita identidad válida, aunque el perfil siga pendiente."""
    await database.verified_user_id()
    result = await database.request(
        "POST", "rest/v1/rpc/accept_invitation", data={"invitation_id": str(invitation_id)},
    )
    return {"invitationId": result}


@router.get("/empresas")
async def customer_accounts(
    session: SessionDependency,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """Empresas activas visibles según RLS; no acepta un alcance impuesto por el cliente."""
    return await session.database.rows("customer_accounts", {
        "select": "id,name", "is_active": "eq.true", "order": "name.asc,id.asc", "limit": limit, "offset": offset,
    })
