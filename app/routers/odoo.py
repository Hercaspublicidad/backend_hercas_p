from fastapi import APIRouter, HTTPException

from app.services.odoo import odoo


router = APIRouter(
    prefix="/odoo",
    tags=["Odoo"]
)


@router.get("/clientes")
async def obtener_clientes(limit: int = 10):

    try:

        clientes = await odoo.call(
            "res.partner",
            "search_read",
            {
                "domain": [
                    ["is_company", "=", True]
                ],
                "fields": [
                    "id",
                    "name",
                    "email",
                    "phone",
                    "vat"
                ],
                "limit": limit
            }
        )

        return {
            "total": len(clientes),
            "clientes": clientes
        }

    except Exception as error:

        raise HTTPException(
            status_code=500,
            detail=str(error)
        )