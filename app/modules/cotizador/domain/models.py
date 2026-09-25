"""Contratos compatibles con los nombres camelCase del piloto Next.js."""

import re
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

MAX_SAFE_INTEGER = 9_007_199_254_740_991


def numeric(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        raise ValueError("Se esperaba un número")
    return value


def date_only(value):
    if type(value) is date:
        return value
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError("La fecha debe usar YYYY-MM-DD")
    return date.fromisoformat(value)


Number = Annotated[Decimal, Field(ge=0, le=MAX_SAFE_INTEGER, allow_inf_nan=False), BeforeValidator(numeric)]
Percent = Annotated[Decimal, Field(ge=0, le=100, allow_inf_nan=False), BeforeValidator(numeric)]
Cop = Annotated[int, Field(ge=0, le=MAX_SAFE_INTEGER), BeforeValidator(numeric)]
DateOnly = Annotated[date, BeforeValidator(date_only)]
NonEmpty = Annotated[str, Field(min_length=1, max_length=500)]
CustomerType = Literal["normal", "agency", "corporate", "ut_contract"]


class Model(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True,
        extra="forbid", str_strip_whitespace=True, allow_inf_nan=False,
    )


class RentalLine(Model):
    unit_price: Number
    periods: Number


class AdditionalLine(Model):
    id: str | None = None
    description: str | None = None
    quantity: Number
    unit_price: Number


class QuoteCalculationInput(Model):
    rate: Number = Decimal(0)
    periods: Number = Decimal(0)
    rental_lines: list[RentalLine] | None = Field(default=None, max_length=500)
    additional_lines: list[AdditionalLine] = Field(max_length=500)
    discount_percent: Percent
    tax_percent: Percent


class QuoteTotals(Model):
    rental_subtotal: Cop
    additional_subtotal: Cop
    subtotal: Cop
    discount: Cop
    taxable_base: Cop
    tax: Cop
    total: Cop


class ProductPrice(Model):
    amount: Cop
    state: Literal["pending", "confirmed", "suspended"]
    reviewed_at: DateOnly | None = None
    reviewed_by: NonEmpty | None = None
    cost_amount: Cop | None = None
    cost_source: Literal["odoo"] | None = None

    @model_validator(mode="after")
    def confirmed_price_is_positive(self):
        if self.state == "confirmed" and self.amount == 0:
            raise ValueError("Una tarifa confirmada debe ser mayor que cero")
        return self


class CustomerRule(Model):
    id: NonEmpty
    customer_key: NonEmpty
    scope: Literal["all", "commercial_line", "product"]
    commercial_line: NonEmpty | None = None
    product_id: NonEmpty | None = None
    adjustment_type: Literal["percent", "fixed"]
    value: Number
    starts_on: DateOnly
    ends_on: DateOnly
    active: bool

    @model_validator(mode="after")
    def validate_rule(self):
        if self.ends_on < self.starts_on:
            raise ValueError("La fecha final debe ser igual o posterior a la inicial")
        if self.scope == "product" and not self.product_id:
            raise ValueError("La regla requiere productId")
        if self.scope == "commercial_line" and not self.commercial_line:
            raise ValueError("La regla requiere commercialLine")
        if self.adjustment_type == "percent" and self.value > 100:
            raise ValueError("El porcentaje debe estar entre 0 y 100")
        if self.adjustment_type == "fixed" and self.value != self.value.to_integral_value():
            raise ValueError("El precio fijo debe ser un entero COP")
        return self


class TypeDiscounts(Model):
    normal: Percent
    agency: Percent
    corporate: Percent
    ut_contract: Percent = Field(alias="ut_contract")


class PriceBook(Model):
    version: NonEmpty
    status: Literal["draft", "published"]
    published_at: str | None = None
    published_by: NonEmpty | None = None
    product_prices: dict[str, ProductPrice]
    type_discounts: TypeDiscounts
    customer_rules: list[CustomerRule] = Field(max_length=1000)

    @model_validator(mode="after")
    def validate_publication(self):
        if self.published_at is not None:
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", self.published_at):
                date.fromisoformat(self.published_at)
            elif re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z", self.published_at):
                datetime.fromisoformat(self.published_at.replace("Z", "+00:00"))
            else:
                raise ValueError("Fecha de publicación inválida")
        if self.status == "published" and (not self.published_by or not self.published_at):
            raise ValueError("Un tarifario publicado requiere autor y fecha de publicación")
        return self


class ResolvePriceInput(Model):
    product_id: NonEmpty
    commercial_line: NonEmpty
    customer_key: NonEmpty
    customer_type: CustomerType
    quoted_on: DateOnly


class AvailablePrice(Model):
    available: Literal[True] = True
    base_rate: Cop
    price: Cop
    adjustment_percent: float | None
    rule_label: str
    version: str


class UnavailablePrice(Model):
    available: Literal[False] = False
    state: Literal["pending", "suspended", "missing", "unpublished"]
    reason: str
    version: str


class PriceSimulation(Model):
    price_book: PriceBook
    input: ResolvePriceInput
