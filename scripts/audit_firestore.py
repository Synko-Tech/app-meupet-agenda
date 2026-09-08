#!/usr/bin/env python3
"""Audit Firestore collections for data inconsistencies.

Phase 0 containment: run BEFORE any data migration. Read-only script that
iterates `payments`, `customerPackages`, `appointments`, `packageUsage` and
`users` and prints inconsistencies found.

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/audit_firestore.py [--project my-project] [--token <access-token>]

Exit code is 0 even when findings are printed. A non-zero exit code means a
real error (bad credentials, project not found, etc.).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

try:
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
except ImportError:  # pragma: no cover - import guard for dry-run checks
    firestore = None  # type: ignore[assignment]
    Credentials = None  # type: ignore[assignment]

COLLECTIONS = (
    "payments",
    "customerPackages",
    "appointments",
    "packageUsage",
    "users",
)

PAYMENT_STATUS_PAID = "PAGO"
PACKAGE_STATUS_ACTIVE = "ATIVO"
APPOINTMENT_STATUS_CANCELED = "CANCELADO"

# Schema do perfil completo (grava apos a Tarefa 8/9 em completeOwnProfile).
PROFILE_SCHEMA_VERSION = 2


@dataclass
class AuditResult:
    """Accumulates findings for a single audit run."""

    findings: list[dict[str, Any]] = field(default_factory=list)

    def add(self, check: str, doc_id: str, **details: Any) -> None:
        entry = {"check": check, "id": doc_id}
        entry.update(details)
        self.findings.append(entry)


def parse_timestamp(value: Any) -> Optional[datetime]:
    """Convert a Firestore timestamp value to an aware datetime.

    Modern google-cloud-firestore returns aware ``datetime`` objects for
    server timestamps; seed scripts may store ISO strings. A duck-typed
    fallback handles protobuf ``Timestamp`` objects if ever present.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    to_datetime = getattr(value, "ToDatetime", None)
    if callable(to_datetime):
        parsed = to_datetime()
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def load_collection(db: Any, name: str) -> list[tuple[str, dict[str, Any]]]:
    """Return [(doc_id, data)] for a collection, skipping empty docs."""
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(name).stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def check_paid_without_history(payments: list[tuple[str, dict]], result: AuditResult) -> int:
    """Check 1: PAGO payments without a `statusHistory` field."""
    for doc_id, data in payments:
        if data.get("status") == PAYMENT_STATUS_PAID and "statusHistory" not in data:
            result.add(
                "paid_without_status_history",
                doc_id,
                client_id=data.get("id_cliente"),
                valor=data.get("valor"),
                data_pagamento=str(data.get("data_pagamento")),
            )
    return 1


def check_active_packages_without_paid_payment(
    packages: list[tuple[str, dict]], payments: list[tuple[str, dict]], result: AuditResult
) -> int:
    """Check 2: ATIVO customerPackages whose linked payment is not PAGO.

    Joins by `id_pacote_cliente` on payments. Flags packages with no linked
    payment at all, and packages whose linked payment is PENDENTE (or any
    non-PAGO status).
    """
    payments_by_package: dict[str, list[tuple[str, dict]]] = {}
    for doc_id, data in payments:
        package_id = data.get("id_pacote_cliente")
        if package_id:
            payments_by_package.setdefault(package_id, []).append((doc_id, data))

    for doc_id, data in packages:
        if data.get("status") != PACKAGE_STATUS_ACTIVE:
            continue
        linked = payments_by_package.get(doc_id, [])
        if not linked:
            result.add(
                "active_package_without_payment",
                doc_id,
                client_id=data.get("id_cliente"),
                package_name=data.get("packageName"),
            )
        elif not any(p[1].get("status") == PAYMENT_STATUS_PAID for p in linked):
            statuses = sorted({str(p[1].get("status")) for p in linked})
            result.add(
                "active_package_without_paid_payment",
                doc_id,
                client_id=data.get("id_cliente"),
                payment_ids=[p[0] for p in linked],
                payment_statuses=statuses,
            )
    return 2


def _as_int(value: Any) -> Optional[int]:
    """Coerce an int (or an integral float Firestore may return) to int."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def check_credit_bounds(packages: list[tuple[str, dict]], result: AuditResult) -> int:
    """Check 3: customerPackages with used credits out of [0, total]."""
    for doc_id, data in packages:
        total = _as_int(data.get("creditos_totais"))
        used = _as_int(data.get("creditos_usados"))
        if total is None or used is None:
            result.add(
                "credits_non_integer",
                doc_id,
                creditos_totais=data.get("creditos_totais"),
                creditos_usados=data.get("creditos_usados"),
            )
            continue
        if used < 0:
            result.add(
                "negative_used_credits",
                doc_id,
                creditos_totais=total,
                creditos_usados=used,
            )
        elif used > total:
            result.add(
                "used_credits_exceed_total",
                doc_id,
                creditos_totais=total,
                creditos_usados=used,
            )
    return 3


def check_overlapping_appointments(
    appointments: list[tuple[str, dict]], result: AuditResult
) -> int:
    """Check 4: overlapping appointments for the same collaborator on the same day.

    Overlap: start(A) < end(B) and start(B) < end(A). CANCELADO excluded.
    """
    active: list[tuple[str, dict, datetime, datetime, str]] = []
    for doc_id, data in appointments:
        if data.get("status") == APPOINTMENT_STATUS_CANCELED:
            continue
        start = parse_timestamp(data.get("data_hora_inicio"))
        end = parse_timestamp(data.get("data_hora_fim"))
        if start is None or end is None:
            print(
                f"  [warn] check 4: {doc_id}: data_hora_inicio/data_hora_fim "
                "unparseable; skipped",
            )
            continue
        day_key = data.get("dayKey") or start.strftime("%Y-%m-%d")
        active.append((doc_id, data, start, end, str(day_key)))

    buckets: dict[tuple[str, str], list[tuple[str, datetime, datetime]]] = {}
    for doc_id, data, start, end, day_key in active:
        collab = data.get("id_colaborador") or "?"
        buckets.setdefault((str(collab), day_key), []).append((doc_id, start, end))

    for key, items in buckets.items():
        ordered = sorted(items, key=lambda i: (i[1], i[2]))
        for i in range(len(ordered) - 1):
            id_a, start_a, end_a = ordered[i]
            id_b, start_b, end_b = ordered[i + 1]
            if start_a < end_b and start_b < end_a:
                result.add(
                    "overlapping_appointments",
                    id_a,
                    collab=key[0],
                    day_key=key[1],
                    overlaps_with=id_b,
                    start_a=start_a.isoformat(),
                    end_a=end_a.isoformat(),
                    start_b=start_b.isoformat(),
                    end_b=end_b.isoformat(),
                )
    return 4


def check_canceled_package_usage(
    appointments: list[tuple[str, dict]],
    usages: list[tuple[str, dict]],
    result: AuditResult,
) -> int:
    """Check 5: CANCELADO appointment still has a packageUsage record.

    packageUsage has no `estornado` field yet, so any usage record whose
    `id_agendamento` matches a CANCELADO appointment is the anomaly. Records
    with `estornado == True` (future-proofing) are excluded.
    """
    usage_by_appointment: dict[str, list[tuple[str, dict]]] = {}
    for doc_id, data in usages:
        if data.get("estornado") is True:
            print(
                f"  [warn] check 5: {doc_id}: usage record skipped "
                "(estornado already True)",
            )
            continue
        appointment_id = data.get("id_agendamento")
        if appointment_id:
            usage_by_appointment.setdefault(str(appointment_id), []).append((doc_id, data))

    for doc_id, data in appointments:
        if data.get("status") != APPOINTMENT_STATUS_CANCELED:
            continue
        if not data.get("id_pacote_cliente"):
            continue
        linked = usage_by_appointment.get(doc_id, [])
        if linked:
            result.add(
                "canceled_appointment_with_usage",
                doc_id,
                client_id=data.get("id_cliente"),
                id_pacote_cliente=data.get("id_pacote_cliente"),
                usage_ids=[u[0] for u in linked],
                used_at=[str(u[1].get("usedAt")) for u in linked],
            )
    return 5


def check_inactive_users(users: list[tuple[str, dict]], result: AuditResult) -> int:
    """Check 6: users with ativo == false (informational)."""
    for doc_id, data in users:
        if data.get("ativo") is False:
            result.add(
                "inactive_user",
                doc_id,
                name=data.get("nome"),
                email=data.get("email"),
                role=data.get("role") or data.get("tipo_usuario"),
            )
    return 6


def check_profile_schema(users: list[tuple[str, dict]], result: AuditResult) -> int:
    """Check 7: incomplete profiles and profile-schema inconsistencies.

    Counts (never prints values — the report only totals by check):

    - ``incomplete_profile``: ``profileComplete`` missing or false. Legacy
      real users stay incomplete until they complete the form themselves; the
      migration must never invent CPF/address, so this is informational.
    - ``profile_schema_mismatch``: completed profiles (``profileComplete`` is
      true) whose ``schemaVersion`` is missing or different from 2.

    ``userPrivate/{uid}`` is never read, so no CPF value can reach the report.
    """
    for doc_id, data in users:
        role = data.get("role") or data.get("tipo_usuario")
        if data.get("profileComplete") is not True:
            result.add("incomplete_profile", doc_id, role=role)
            continue
        if data.get("schemaVersion") != PROFILE_SCHEMA_VERSION:
            result.add(
                "profile_schema_mismatch",
                doc_id,
                schema_version=data.get("schemaVersion"),
                role=role,
            )
    return 7


def print_report(result: AuditResult) -> None:
    """Print findings grouped by check, then a summary count per check."""
    by_check: dict[str, list[dict[str, Any]]] = {}
    for finding in result.findings:
        by_check.setdefault(finding["check"], []).append(finding)

    print("\n=== AUDIT FINDINGS ===")
    for check, items in by_check.items():
        print(f"\n[{check}] ({len(items)}):")
        for item in items:
            print(f"  {item['id']}: {item}")

    print("\n=== SUMMARY ===")
    check_names = (
        "paid_without_status_history",
        "active_package_without_payment",
        "active_package_without_paid_payment",
        "credits_non_integer",
        "negative_used_credits",
        "used_credits_exceed_total",
        "overlapping_appointments",
        "canceled_appointment_with_usage",
        "inactive_user",
        "incomplete_profile",
        "profile_schema_mismatch",
    )
    for name in check_names:
        print(f"  {name}: {len(by_check.get(name, []))}")
    print(f"  TOTAL: {len(result.findings)}")
    print("  (exit code 0: findings are informational, not errors)")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id (default: from ADC)")
    parser.add_argument(
        "--token",
        help="OAuth2 access token (alternative to GOOGLE_APPLICATION_CREDENTIALS)",
    )
    args = parser.parse_args(argv)

    if firestore is None:
        print(
            "ERROR: google-cloud-firestore is not installed. "
            "Run: pip install google-cloud-firestore",
            file=sys.stderr,
        )
        return 2

    try:
        if args.token:
            if Credentials is None:
                raise RuntimeError("google-auth not available for --token")
            creds = Credentials(token=args.token)
            db = firestore.Client(project=args.project, credentials=creds)
        else:
            db = firestore.Client(project=args.project)
    except Exception as exc:  # noqa: BLE001 - report any init failure as fatal
        print(f"ERROR: failed to init Firestore client: {exc}", file=sys.stderr)
        return 1

    try:
        result = AuditResult()
        loaded: dict[str, list[tuple[str, dict[str, Any]]]] = {}
        for name in COLLECTIONS:
            loaded[name] = load_collection(db, name)
            print(f"Loaded {len(loaded[name])} docs from '{name}'")

        payments = loaded["payments"]
        packages = loaded["customerPackages"]
        appointments = loaded["appointments"]
        usages = loaded["packageUsage"]
        users = loaded["users"]

        _ = (
            check_paid_without_history(payments, result),
            check_active_packages_without_paid_payment(packages, payments, result),
            check_credit_bounds(packages, result),
            check_overlapping_appointments(appointments, result),
            check_canceled_package_usage(appointments, usages, result),
            check_inactive_users(users, result),
            check_profile_schema(users, result),
        )

        print_report(result)
        return 0
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: audit failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
