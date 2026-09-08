#!/usr/bin/env python3
"""Reconcile ATIVO customerPackages against their payments (report only).

Phase 5 data check (Task 16). For every customerPackage with status ATIVO,
find the payments linked through `id_pacote_cliente` and flag packages with no
confirmed payment: no linked payment at all, or only PENDENTE/CANCELADO (any
non-PAGO) payments. Packages with at least one PAGO payment are OK.

READ-ONLY: nothing is written or mutated. Findings are printed and the exit
code is 0 even when packages are flagged (same contract as
scripts/audit_firestore.py); a non-zero exit code means a real error.

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/reconcile_packages_payments.py [--project my-project] [--token <access-token>]

The Firestore emulator is used automatically when FIRESTORE_EMULATOR_HOST is set.
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any, Optional

try:
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
except ImportError:  # pragma: no cover - import guard for dry-run checks
    firestore = None  # type: ignore[assignment]
    Credentials = None  # type: ignore[assignment]

PAYMENT_STATUS_PAID = "PAGO"
PAYMENT_STATUS_PENDING = "PENDENTE"
PAYMENT_STATUS_CANCELED = "CANCELADO"
PACKAGE_STATUS_ACTIVE = "ATIVO"

FLAG_NO_CONFIRMED_PAYMENT = "sem pagamento confirmado"
STATUS_OK = "OK"


@dataclass
class ReconcileResult:
    """Accumulates per-package reconcile entries."""

    packages: list[dict[str, Any]] = field(default_factory=list)


def load_collection(db: Any, name: str) -> list[tuple[str, dict[str, Any]]]:
    """Return [(doc_id, data)] for a collection, skipping empty docs."""
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(name).stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def reconcile_packages(
    packages: list[tuple[str, dict[str, Any]]],
    payments: list[tuple[str, dict[str, Any]]],
) -> ReconcileResult:
    """Classify each ATIVO package as OK or 'sem pagamento confirmado'.

    A package is OK iff at least one of its linked payments has status PAGO.
    Linked means the payment's ``id_pacote_cliente`` equals the package doc id.
    """
    payments_by_package: dict[str, list[tuple[str, dict[str, Any]]]] = defaultdict(list)
    for doc_id, data in payments:
        package_id = data.get("id_pacote_cliente")
        if package_id:
            payments_by_package[str(package_id)].append((doc_id, data))

    result = ReconcileResult()
    for doc_id, data in packages:
        if data.get("status") != PACKAGE_STATUS_ACTIVE:
            continue
        linked = payments_by_package.get(doc_id, [])
        statuses = sorted({str(p[1].get("status")) for p in linked})
        has_paid = any(p[1].get("status") == PAYMENT_STATUS_PAID for p in linked)
        result.packages.append(
            {
                "package_id": doc_id,
                "client_id": data.get("id_cliente"),
                "package_name": data.get("packageName"),
                "status": STATUS_OK if has_paid else FLAG_NO_CONFIRMED_PAYMENT,
                "payment_count": len(linked),
                "payment_statuses": statuses,
                "payment_ids": [p[0] for p in linked],
            }
        )
    return result


def print_report(result: ReconcileResult) -> None:
    """Print per-package status grouped by verdict, then a summary."""
    flagged = [entry for entry in result.packages if entry["status"] != STATUS_OK]
    ok = [entry for entry in result.packages if entry["status"] == STATUS_OK]

    print("\n=== PACOTES SEM PAGAMENTO CONFIRMADO ===")
    if not flagged:
        print("  (nenhum)")
    for entry in flagged:
        print(
            f"  {entry['package_id']}: cliente {entry['client_id']} "
            f"({entry['package_name']}), pagamentos={entry['payment_count']}, "
            f"status={entry['payment_statuses']}, ids={entry['payment_ids']}"
        )

    print("\n=== PACOTES OK (pagamento PAGO) ===")
    if not ok:
        print("  (nenhum)")
    for entry in ok:
        print(
            f"  {entry['package_id']}: cliente {entry['client_id']} "
            f"({entry['package_name']}), pagamentos={entry['payment_count']}"
        )

    print("\n=== RESUMO ===")
    print(f"  Pacotes ATIVO verificados: {len(result.packages)}")
    print(f"  OK (pagamento PAGO): {len(ok)}")
    print(f"  Sem pagamento confirmado: {len(flagged)}")
    print("  (somente leitura: nenhum dado foi alterado)")
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
        loaded: dict[str, list[tuple[str, dict[str, Any]]]] = {}
        for name in ("customerPackages", "payments"):
            loaded[name] = load_collection(db, name)
            print(f"Loaded {len(loaded[name])} docs from '{name}'")

        result = reconcile_packages(
            loaded["customerPackages"], loaded["payments"]
        )
        print_report(result)
        return 0
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: reconcile failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
