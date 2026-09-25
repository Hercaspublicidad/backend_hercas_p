import copy
import unittest
from datetime import date, datetime, timedelta, timezone

from pydantic import ValidationError

from app.modules.cotizador.domain.availability import hold_expires_at, overlaps, validate_reservation
from app.modules.cotizador.domain.models import PriceBook, QuoteCalculationInput, ResolvePriceInput
from app.modules.cotizador.domain.pricing import resolve_price
from app.modules.cotizador.domain.quotes import calculate_quote


def book_data():
    return {
        "version": "2026-09", "status": "published", "publishedAt": "2026-09-01", "publishedBy": "Gabriel",
        "typeDiscounts": {"normal": 0, "agency": 10, "corporate": 5, "ut_contract": 15},
        "productPrices": {"v1": {"amount": 10_000_000, "state": "confirmed"}},
        "customerRules": [
            {"id": "r1", "customerKey": "postobon", "scope": "all", "adjustmentType": "percent", "value": 12, "startsOn": "2026-09-01", "endsOn": "2026-12-31", "active": True},
            {"id": "r2", "customerKey": "postobon", "scope": "commercial_line", "commercialLine": "OOH", "adjustmentType": "percent", "value": 11, "startsOn": "2026-09-01", "endsOn": "2026-12-31", "active": True},
            {"id": "r3", "customerKey": "postobon", "scope": "product", "productId": "v1", "adjustmentType": "fixed", "value": 8_700_000, "startsOn": "2026-09-01", "endsOn": "2026-12-31", "active": True},
        ],
    }


def price_input(**changes):
    return ResolvePriceInput.model_validate({
        "productId": "v1", "commercialLine": "OOH", "customerKey": " Postobón ",
        "customerType": "agency", "quotedOn": "2026-09-09", **changes,
    })


class QuoteTests(unittest.TestCase):
    def calculate(self, **changes):
        return calculate_quote(QuoteCalculationInput.model_validate({
            "rate": 2_000_000, "periods": 2,
            "additionalLines": [{"quantity": 2, "unitPrice": 300_000}],
            "discountPercent": 10, "taxPercent": 19, **changes,
        }))

    def test_original_next_case(self):
        self.assertEqual(self.calculate().model_dump(by_alias=True), {
            "rentalSubtotal": 4_000_000, "additionalSubtotal": 600_000, "subtotal": 4_600_000,
            "discount": 460_000, "taxableBase": 4_140_000, "tax": 786_600, "total": 4_926_600,
        })

    def test_multiple_locations(self):
        result = self.calculate(rentalLines=[{"unitPrice": 10_000_000, "periods": 2}, {"unitPrice": 8_000_000, "periods": 1}], additionalLines=[], discountPercent=0, taxPercent=0)
        self.assertEqual(result.total, 28_000_000)

    def test_half_rounding_and_subtotal_before_rounding(self):
        # Python round(2.5) == 2; el piloto usa Math.round(2.5) == 3.
        self.assertEqual(self.calculate(rate=2.5, periods=1, additionalLines=[], discountPercent=0, taxPercent=0).total, 3)
        result = self.calculate(rentalLines=[{"unitPrice": 0.4, "periods": 1}, {"unitPrice": 0.4, "periods": 1}], additionalLines=[], discountPercent=0, taxPercent=0)
        self.assertEqual(result.total, 1)

    def test_empty_lines_override_legacy_rate(self):
        self.assertEqual(self.calculate(rentalLines=[], additionalLines=[]).total, 0)

    def test_invalid_numbers(self):
        for changes in ({"rate": -1}, {"rate": True}, {"rate": "10"}, {"rate": float("nan")}, {"rate": float("inf")}, {"discountPercent": 101}, {"taxPercent": -1}):
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                self.calculate(**changes)

    def test_discount_boundaries(self):
        self.assertEqual(self.calculate(discountPercent=100).total, 0)
        self.assertEqual(self.calculate(discountPercent=0, taxPercent=0).total, 4_600_000)

    def test_output_overflow(self):
        with self.assertRaises(ValueError):
            self.calculate(rate=9_007_199_254_740_991, periods=2)


class PricingTests(unittest.TestCase):
    def test_rule_priority(self):
        book = book_data()
        for scopes, expected in [({"all", "commercial_line", "product"}, 8_700_000), ({"all", "commercial_line"}, 8_900_000), ({"all"}, 8_800_000), (set(), 9_000_000)]:
            data = {**book, "customerRules": [rule for rule in book["customerRules"] if rule["scope"] in scopes]}
            with self.subTest(scopes=scopes):
                self.assertEqual(resolve_price(PriceBook.model_validate(data), price_input()).price, expected)

    def test_each_customer_type(self):
        for customer_type, expected in [("normal", 10_000_000), ("agency", 9_000_000), ("corporate", 9_500_000), ("ut_contract", 8_500_000)]:
            self.assertEqual(resolve_price(PriceBook.model_validate(book_data()), price_input(customerType=customer_type, customerKey="otro")).price, expected)

    def test_date_boundaries_and_expired_rule(self):
        for quoted_on, expected in [("2026-09-01", 8_700_000), ("2026-12-31", 8_700_000), ("2027-01-01", 9_000_000), ("2026-08-31", 9_000_000)]:
            self.assertEqual(resolve_price(PriceBook.model_validate(book_data()), price_input(quotedOn=quoted_on)).price, expected)

    def test_inactive_rules(self):
        data = book_data()
        for rule in data["customerRules"]:
            rule["active"] = False
        self.assertEqual(resolve_price(PriceBook.model_validate(data), price_input()).price, 9_000_000)

    def test_unavailable_prices(self):
        for state in ("pending", "suspended"):
            data = book_data()
            data["productPrices"]["v1"]["state"] = state
            result = resolve_price(PriceBook.model_validate(data), price_input())
            self.assertFalse(result.available)
            self.assertEqual(result.state, state)
        self.assertEqual(resolve_price(PriceBook.model_validate(book_data()), price_input(productId="missing")).state, "missing")

    def test_drafts_cannot_be_quoted(self):
        data = book_data()
        data.update(status="draft", publishedAt=None, publishedBy=None)
        self.assertEqual(resolve_price(PriceBook.model_validate(data), price_input()).state, "unpublished")

    def test_publication_attribution_required(self):
        for field in ("publishedBy", "publishedAt"):
            data = book_data()
            data[field] = None
            with self.subTest(field=field), self.assertRaises(ValidationError):
                PriceBook.model_validate(data)

    def test_dates_and_scope_validation(self):
        for change in ({"startsOn": "2026-02-30"}, {"startsOn": "2026-09-01T00:00:00Z"}, {"endsOn": "2026-08-01"}, {"scope": "product"}, {"scope": "commercial_line"}, {"value": 101}, {"adjustmentType": "fixed", "value": 1.5}):
            data = book_data()
            data["customerRules"] = [{**data["customerRules"][0], **change}]
            with self.subTest(change=change), self.assertRaises(ValidationError):
                PriceBook.model_validate(data)

    def test_invalid_product_prices(self):
        for amount in (0, -1, 1.5, float("inf"), 9_007_199_254_740_992):
            data = book_data()
            data["productPrices"]["v1"]["amount"] = amount
            with self.subTest(amount=amount), self.assertRaises(ValidationError):
                PriceBook.model_validate(data)

    def test_does_not_mutate_input(self):
        book = PriceBook.model_validate(book_data())
        before = copy.deepcopy(book)
        resolve_price(book, price_input())
        self.assertEqual(book, before)


class AvailabilityTests(unittest.TestCase):
    def test_72_hour_expiry_and_reservation(self):
        created = datetime(2026, 9, 9, 10, tzinfo=timezone.utc)
        expires = hold_expires_at(created)
        self.assertEqual(expires, datetime(2026, 9, 12, 10, tzinfo=timezone.utc))
        validate_reservation(created, expires - timedelta(seconds=1), "soporte")
        with self.assertRaises(ValueError):
            validate_reservation(created, expires, "soporte")
        with self.assertRaises(ValueError):
            validate_reservation(created, created, " ")

    def test_inclusive_overlap(self):
        self.assertTrue(overlaps(date(2026, 9, 1), date(2026, 9, 10), date(2026, 9, 10), date(2026, 9, 20)))
        self.assertFalse(overlaps(date(2026, 9, 1), date(2026, 9, 9), date(2026, 9, 10), date(2026, 9, 20)))

    def test_reversed_dates_and_naive_timestamps(self):
        with self.assertRaises(ValueError):
            overlaps(date(2026, 9, 20), date(2026, 9, 10), date(2026, 9, 1), date(2026, 9, 30))
        with self.assertRaises(ValueError):
            hold_expires_at(datetime(2026, 9, 9))
