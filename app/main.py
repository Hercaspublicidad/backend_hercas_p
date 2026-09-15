from fastapi import FastAPI

from app.config import settings
from app.routers.health import router as health_router
from app.routers.odoo import router as odoo_router


app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
    description="Backend de integración entre Odoo 19 y sistemas externos"
)


app.include_router(health_router)
app.include_router(odoo_router)


@app.get("/")
async def root():

    return {
        "message": "Sistema Externos API Odoo",
        "version": "0.1.0"
    }