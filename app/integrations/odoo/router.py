from typing import Annotated

from fastapi import APIRouter, Query, Request

from app.core.auth import SessionDependency, require_roles
from app.integrations.odoo.client import OdooClient

router = APIRouter(prefix="/integraciones/odoo", tags=["Integraciones · Odoo"])


@router.get("/clientes")
async def obtener_clientes(
    request: Request, session: SessionDependency,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
):
    require_roles(session, "sales", "systems_admin")
    odoo = OdooClient(request.app.state.http, request.app.state.settings)
    clientes = await odoo.call("res.partner", "search_read", {
        "domain": [["is_company", "=", True]],
        "fields": ["id", "name", "email", "phone", "vat"], "limit": limit,
    })
    return {"total": len(clientes), "clientes": clientes}
