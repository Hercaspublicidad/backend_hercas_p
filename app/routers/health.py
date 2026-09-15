from fastapi import APIRouter

router = APIRouter(
    tags=["Sistema"]
)


@router.get("/health")
async def health():

    return {
        "status": "ok",
        "service": "Sistema Externos API Odoo"
    }