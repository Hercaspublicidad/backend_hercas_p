from fastapi import APIRouter, Request

router = APIRouter(tags=["Sistema"])


@router.get("/health")
async def health(request: Request):
    """Liveness del proceso; no comprueba conexiones externas."""
    return {"status": "ok", "service": request.app.state.settings.APP_NAME}
