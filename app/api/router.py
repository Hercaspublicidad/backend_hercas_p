"""Composición explícita de las rutas compartidas y módulos habilitados."""

from fastapi import APIRouter

from app.api.auth import router as auth_router
from app.core.config import Settings
from app.integrations.odoo.router import router as odoo_router


def create_api_router(settings: Settings) -> APIRouter:
    router = APIRouter(prefix="/api/v1")
    router.include_router(auth_router)
    router.include_router(odoo_router)
    if "cotizador" in settings.ENABLED_MODULES:
        from app.modules.cotizador.router import router as cotizador_router

        router.include_router(cotizador_router)
    return router
