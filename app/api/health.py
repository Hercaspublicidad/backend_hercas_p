import httpx
from fastapi import APIRouter, Request

from app.core.errors import ServiceError

router = APIRouter(tags=["Sistema"])


@router.get("/health")
async def health(request: Request):
    """Confirma que el proceso FastAPI está respondiendo."""

    return {
        "status": "ok",
        "service": request.app.state.settings.APP_NAME,
    }


@router.get("/ready")
async def readiness(request: Request):
    """Confirma que la API puede comunicarse con Supabase Auth."""

    settings = request.app.state.settings

    if not settings.SUPABASE_URL:
        raise ServiceError(503, "Supabase no está configurado")

    if not settings.SUPABASE_PUBLISHABLE_KEY:
        raise ServiceError(503, "Supabase no está configurado")

    publishable_key = (
        settings.SUPABASE_PUBLISHABLE_KEY.get_secret_value()
    )

    try:
        response = await request.app.state.http.get(
            f"{settings.SUPABASE_URL.rstrip('/')}/auth/v1/health",
            headers={"apikey": publishable_key},
            timeout=min(settings.HTTP_TIMEOUT_SECONDS, 5),
        )
    except httpx.TimeoutException as error:
        raise ServiceError(
            503,
            "Supabase no está disponible",
        ) from error
    except httpx.RequestError as error:
        raise ServiceError(
            503,
            "Supabase no está disponible",
        ) from error

    if response.is_error:
        raise ServiceError(
            503,
            "Supabase no está disponible",
        )

    return {
        "status": "ready",
        "supabase": "available",
    }