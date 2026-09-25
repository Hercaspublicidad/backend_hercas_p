"""Cálculo COP: redondear subtotales, descuento e IVA en ese orden."""

from decimal import Decimal, ROUND_HALF_UP, localcontext

from app.modules.cotizador.domain.models import MAX_SAFE_INTEGER, QuoteCalculationInput, QuoteTotals, RentalLine


def cop(value: Decimal) -> int:
    result = int(value.to_integral_value(rounding=ROUND_HALF_UP))
    if result < 0 or result > MAX_SAFE_INTEGER:
        raise ValueError("El resultado excede el rango monetario permitido")
    return result


def calculate_quote(data: QuoteCalculationInput) -> QuoteTotals:
    lines = data.rental_lines
    if lines is None:
        lines = [RentalLine(unit_price=data.rate, periods=data.periods)]
    with localcontext() as context:
        context.prec = 60
        rental = cop(sum((line.unit_price * line.periods for line in lines), Decimal(0)))
        additional = cop(sum((line.unit_price * line.quantity for line in data.additional_lines), Decimal(0)))
        subtotal = cop(Decimal(rental + additional))
        discount = cop(Decimal(subtotal) * data.discount_percent / 100)
        base = subtotal - discount
        tax = cop(Decimal(base) * data.tax_percent / 100)
        total = cop(Decimal(base + tax))
    return QuoteTotals(
        rental_subtotal=rental, additional_subtotal=additional, subtotal=subtotal,
        discount=discount, taxable_base=base, tax=tax, total=total,
    )
