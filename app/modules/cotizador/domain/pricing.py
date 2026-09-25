import unicodedata
from decimal import Decimal, localcontext

from app.modules.cotizador.domain.models import AvailablePrice, PriceBook, ResolvePriceInput, UnavailablePrice
from app.modules.cotizador.domain.quotes import cop


def customer_key(value: str) -> str:
    normalized = unicodedata.normalize("NFD", value)
    return "".join(char for char in normalized if not "\u0300" <= char <= "\u036f").strip().lower()


def resolve_price(book: PriceBook, data: ResolvePriceInput) -> AvailablePrice | UnavailablePrice:
    # La simulación no confiere autoridad al tarifario recibido por HTTP.
    if book.status != "published":
        return UnavailablePrice(state="unpublished", reason="El tarifario aún no está publicado.", version=book.version)
    product = book.product_prices.get(data.product_id)
    if product is None:
        return UnavailablePrice(state="missing", reason="Este producto no tiene una tarifa mensual configurada.", version=book.version)
    if product.state != "confirmed":
        reasons = {
            "pending": "La tarifa está pendiente de revisión mensual.",
            "suspended": "La tarifa está suspendida y no se puede cotizar.",
        }
        return UnavailablePrice(state=product.state, reason=reasons[product.state], version=book.version)
    active = [rule for rule in book.customer_rules if rule.active
              and customer_key(rule.customer_key) == customer_key(data.customer_key)
              and rule.starts_on <= data.quoted_on <= rule.ends_on]
    selected = next((rule for scope in ("product", "commercial_line", "all") for rule in active
                     if rule.scope == scope
                     and (scope != "product" or rule.product_id == data.product_id)
                     and (scope != "commercial_line" or rule.commercial_line == data.commercial_line)), None)
    percent = getattr(book.type_discounts, data.customer_type)
    label = f"Descuento {data.customer_type}" if percent else "Tarifa normal"
    if selected:
        scope_label = {"product": "para el producto", "commercial_line": "para la línea", "all": "general del cliente"}[selected.scope]
        if selected.adjustment_type == "fixed":
            label = "Precio fijo general del cliente" if selected.scope == "all" else f"Precio fijo del cliente {scope_label}"
            return AvailablePrice(base_rate=product.amount, price=int(selected.value), adjustment_percent=None, rule_label=label, version=book.version)
        percent = selected.value
        label = "Acuerdo porcentual general del cliente" if selected.scope == "all" else f"Acuerdo porcentual del cliente {scope_label}"
    with localcontext() as context:
        context.prec = 60
        price = cop(Decimal(product.amount) * (1 - percent / 100))
    return AvailablePrice(base_rate=product.amount, price=price, adjustment_percent=float(percent), rule_label=label, version=book.version)
