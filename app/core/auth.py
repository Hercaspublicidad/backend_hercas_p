from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import ServiceError
from app.integrations.supabase.client import SupabaseGateway

bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Session:
    user_id: str
    roles: frozenset[str]
    database: SupabaseGateway


async def require_database(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> SupabaseGateway:
    if credentials is None:
        raise ServiceError(401, "Se requiere una sesión")
    if len(credentials.credentials) > request.app.state.settings.MAX_BEARER_TOKEN_LENGTH:
        raise ServiceError(401, "Sesión inválida o vencida")
    return SupabaseGateway(request.app.state.http, request.app.state.settings, credentials.credentials)


DatabaseDependency = Annotated[SupabaseGateway, Depends(require_database)]


async def require_session(database: DatabaseDependency) -> Session:
    user_id, roles = await database.authenticated_identity()
    return Session(user_id, roles, database)


SessionDependency = Annotated[Session, Depends(require_session)]


def require_roles(session: Session, *roles: str) -> None:
    if not session.roles.intersection(roles):
        raise ServiceError(403, "No tienes permisos para esta operación")
