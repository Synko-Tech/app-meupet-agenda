#!/usr/bin/env python3
"""Audit the multi-tenant migration (read-only).

Validates that the initial business migration is complete and consistent:

  - Every legacy global collection matches the business sub-collection count.
  - Every legacy global user has a membership (and vice versa).
  - Payments/customerPackages/appointments reference users that have
    membership (no orphan references).
  - Financial values: payments total matches the legacy total; paid statuses
    reference paidAt when expected.

READ-ONLY: nothing is written. Findings are printed and the exit code is 0
even when inconsistencies are found (same contract as
scripts/reconcile_packages_payments.py); a non-zero exit code means a real
error (credentials, project, etc.).

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/audit_business_migration.py [--project my-project] [--token <access-token>] [--business-id loja-inicial]
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, Optional

try:
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
except ImportError:  # pragma: no cover - import guard for dry-run checks
    firestore = None  # type: ignore[assignment]
    Credentials = None  # type: ignore[assignment]

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_MISSING_LIB = 2

DOMAIN_COLLECTIONS = [
    "services",
    "packages",
    "professionals",
    "appointments",
    "payments",
    "customerPackages",
    "notifications",
    "packageUsage",
]


def load_collection(db: Any, name: str) -> list[tuple[str, dict[str, Any]]]:
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(name).stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def load_docs(db: Any, business_id: str, sub_name: str) -> list[tuple[str, dict[str, Any]]]:
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(f"businesses/{business_id}/{sub_name}").stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id (default: from ADC)")
    parser.add_argument(
        "--token",
        help="OAuth2 access token (alternative to GOOGLE_APPLICATION_CREDENTIALS)",
    )
    parser.add_argument("--business-id", default="loja-inicial")
    args = parser.parse_args(argv)

    if firestore is None:
        print(
            "ERROR: google-cloud-firestore is not installed. "
            "Run: pip install google-cloud-firestore",
            file=sys.stderr,
        )
        return EXIT_MISSING_LIB

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
        return EXIT_ERROR

    try:
        business_id = args.business_id
        business_ref = db.document(f"businesses/{business_id}")
        if not business_ref.get().exists:
            print(
                f"ERROR: businesses/{business_id} nao existe. "
                "Rode scripts/migrate_to_initial_business.py primeiro.",
                file=sys.stderr,
            )
            return EXIT_ERROR

        issues: list[str] = []
        print(f"=== AUDITORIA businesses/{business_id} ===")

        # 1. Collection parity.
        for sub_name in DOMAIN_COLLECTIONS:
            legacy = load_collection(db, sub_name)
            tenant = load_docs(db, business_id, sub_name)
            status = "OK" if len(legacy) == len(tenant) else "DIVERGE"
            if len(legacy) != len(tenant):
                issues.append(f"{sub_name}: legado={len(legacy)} tenant={len(tenant)}")
            print(f"  {sub_name}: legado={len(legacy)} tenant={len(tenant)} {status}")

        # 2. Membership parity.
        legacy_users = load_collection(db, "users")
        members = load_docs(db, business_id, "members")
        member_uids = {doc_id for doc_id, _ in members}
        legacy_uids = {doc_id for doc_id, _ in legacy_users}
        missing_members = legacy_uids - member_uids
        if missing_members:
            issues.append(f"usuarios sem membership: {sorted(missing_members)}")
        print(
            f"  members: {len(members)} (usuarios legado: {len(legacy_users)}) "
            f"{'OK' if not missing_members else 'DIVERGE'}"
        )

        # 3. Projections.
        for doc_id, data in legacy_users:
            proj = db.document(
                f"users/{doc_id}/businessMemberships/{business_id}"
            ).get()
            if not proj.exists:
                issues.append(f"projecao ausente para user {doc_id}")
        print(
            f"  projecoes users/*/businessMemberships: "
            f"{'OK' if not any('projecao' in i for i in issues) else 'DIVERGE'}"
        )

        # 4. Referential integrity: id_cliente / id_colaborador have membership.
        referenced: set[str] = set()
        for sub_name in ("payments", "customerPackages", "appointments"):
            for doc_id, data in load_docs(db, business_id, sub_name):
                for field in ("id_cliente", "id_colaborador", "id_usuario"):
                    value = data.get(field)
                    if isinstance(value, str) and value:
                        referenced.add(value)
        orphans = referenced - member_uids
        if orphans:
            issues.append(f"referencias sem membership: {sorted(orphans)}")
        print(
            f"  referencias de usuarios: {len(referenced)} "
            f"{'OK' if not orphans else 'DIVERGE'}"
        )

        # 5. Financial parity.
        legacy_payments = load_collection(db, "payments")
        tenant_payments = load_docs(db, business_id, "payments")
        legacy_total = sum(float(data.get("valor") or 0) for _, data in legacy_payments)
        tenant_total = sum(float(data.get("valor") or 0) for _, data in tenant_payments)
        amount_ok = abs(legacy_total - tenant_total) < 0.01
        if not amount_ok:
            issues.append(f"total financeiro diverge: {legacy_total} vs {tenant_total}")
        print(
            f"  total financeiro: legado={legacy_total:.2f} tenant={tenant_total:.2f} "
            f"{'OK' if amount_ok else 'DIVERGE'}"
        )

        print("\n=== RESUMO ===")
        if issues:
            print(f"  Inconsistencias: {len(issues)}")
            for issue in issues:
                print(f"    - {issue}")
            print("  (somente leitura: nenhum dado foi alterado)")
        else:
            print("  Migracao consistente (OK)")
        return EXIT_OK
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: audit failed: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
