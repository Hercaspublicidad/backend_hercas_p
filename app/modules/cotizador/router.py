from datetime import date, datetime, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from app.core.auth import SessionDependency, require_roles
from app.modules.cotizador.domain.models import AvailablePrice, PriceSimulation, QuoteCalculationInput, QuoteTotals, UnavailablePrice
from app.modules.cotizador.domain.pricing import resolve_price
from app.modules.cotizador.domain.quotes import calculate_quote
from app.core.errors import ServiceError

def require_cotizador_access(session: SessionDependency) -> None:
    require_roles(session, "sales", "pricing_manager", "availability_manager", "auditor", "systems_admin")


router = APIRouter(
    prefix="/cotizador", tags=["Cotizador"],
    dependencies=[Depends(require_cotizador_access)],
)
Limit = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0)]


@router.post("/cotizaciones/calcular", response_model=QuoteTotals)
async def simulate_quote(data: QuoteCalculationInput, session: SessionDependency):
    """Simulación aritmética. No guarda ni autoriza tarifas o descuentos."""
    require_roles(session, "sales", "pricing_manager", "systems_admin")
    try:
        return calculate_quote(data)
    except ValueError as error:
        raise ServiceError(422, str(error)) from error


@router.post("/tarifas/simular", response_model=AvailablePrice | UnavailablePrice)
async def simulate_price(data: PriceSimulation, session: SessionDependency):
    """Prueba un tarifario recibido; no lo publica ni lo convierte en oficial."""
    require_roles(session, "pricing_manager", "systems_admin")
    return resolve_price(data.price_book, data.input)


@router.get("/productos")
async def products(session: SessionDependency, limit: Limit = 100, offset: Offset = 0):
    return await session.database.rows("products", {
        "select": "id,external_code,code,name,commercial_unit,family_id,commercial_line_id",
        "visibility": "eq.visible", "is_active": "eq.true", "order": "name.asc,id.asc",
        "limit": limit, "offset": offset,
    })


@router.get("/inventario")
async def inventory(session: SessionDependency, limit: Limit = 100, offset: Offset = 0):
    # Proyección explícita: no exponer source_metadata, costos o evidencias.
    return await session.database.rows("inventory_assets", {
        "select": "id,product_id,canonical_code,name,description,visibility,lifecycle,operational,is_provisional",
        "visibility": "eq.visible", "lifecycle": "eq.active", "order": "canonical_code.asc,id.asc",
        "limit": limit, "offset": offset,
    })


@router.get("/clientes")
async def customers(session: SessionDependency, limit: Limit = 100, offset: Offset = 0):
    return await session.database.rows("customer_accounts", {
        "select": "id,external_code,legal_name:name,trade_name,customer_type_code,tax_identifier",
        "is_active": "eq.true", "order": "name.asc,id.asc", "limit": limit, "offset": offset,
    })


@router.get("/disponibilidades")
async def availability_calendar(
    asset_id: UUID, starts_on: date, ends_on: date, session: SessionDependency,
    limit: Limit = 100, offset: Offset = 0,
):
    """Calendario interno; una consulta no constituye una reserva."""
    if ends_on < starts_on or (ends_on - starts_on).days > 366:
        raise ServiceError(422, "Consulta un intervalo ordenado de hasta 366 días")
    return await session.database.rows("availability_entries", {
        "select": "id,asset_id,starts_on,ends_on,kind,status,expires_at,revision,updated_at",
        "asset_id": f"eq.{asset_id}", "starts_on": f"lte.{ends_on}",
        "ends_on": f"gte.{starts_on}", "status": "eq.active",
        "or": f"(expires_at.is.null,expires_at.gt.{datetime.now(timezone.utc).isoformat()})",
        "order": "starts_on.asc,id.asc", "limit": limit, "offset": offset,
    })


@router.get("/cotizaciones")
async def quotes(session: SessionDependency, limit: Limit = 100, offset: Offset = 0):
    # RLS limita las filas a las autorizadas para el JWT del usuario.
    return await session.database.rows("quotes", {
        "select": "id,quote_number,customer_id,status,currency,subtotal,discount_total,tax_total,total,created_at,updated_at",
        "order": "created_at.desc,id.desc", "limit": limit, "offset": offset,
    })


@router.get("/cotizaciones/{quote_id}")
async def quote_detail(quote_id: UUID, session: SessionDependency):
    rows = await session.database.rows("quotes", {
        "select": "id,quote_number,customer_id,status,currency,customer_snapshot,requirements_snapshot,subtotal,discount_total,tax_total,total,created_at,updated_at",
        "id": f"eq.{quote_id}", "limit": 1,
    })
    if not rows:
        raise ServiceError(404, "Cotización no encontrada")
    return rows[0]
