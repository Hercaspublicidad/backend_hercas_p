"""Reglas temporales puras; la exclusión concurrente corresponde a la BD."""

from datetime import date, datetime, timedelta, timezone

HOLD_HOURS = 72


def validate_range(starts_on: date, ends_on: date) -> None:
    if ends_on < starts_on:
        raise ValueError("La fecha final debe ser igual o posterior a la inicial")


def overlaps(start_a: date, end_a: date, start_b: date, end_b: date) -> bool:
    validate_range(start_a, end_a)
    validate_range(start_b, end_b)
    return start_a <= end_b and start_b <= end_a


def hold_expires_at(created_at: datetime) -> datetime:
    if created_at.tzinfo is None or created_at.utcoffset() is None:
        raise ValueError("La fecha debe incluir zona horaria")
    return created_at.astimezone(timezone.utc) + timedelta(hours=HOLD_HOURS)


def validate_reservation(created_at: datetime, now: datetime, evidence: str) -> None:
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("La fecha debe incluir zona horaria")
    if now < created_at:
        raise ValueError("La reserva no puede preceder a la separación")
    if now >= hold_expires_at(created_at):
        raise ValueError("La separación ya venció")
    if not evidence.strip():
        raise ValueError("La reserva requiere soporte de aceptación")
