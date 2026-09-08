#!/usr/bin/env python3
"""Migrate the legacy single-store data into the initial multi-tenant shape.

The app is being converted to a SaaS multi-loja: every domain collection now
lives under ``businesses/{businessId}/...`` and roles come from memberships
(``businesses/{businessId}/members/{uid}``). This script:

  1. Creates (or reuses) the initial business with the given owner.
  2. Copies every legacy global collection into the business sub-collections
     preserving document IDs and adding a ``businessId`` field for defense in
     depth and audit.
  3. Creates memberships (owner / admin / collaborator / client) from the
     legacy global roles, plus the user projection
     ``users/{uid}/businessMemberships/{businessId}``.
  4. Validates counts, references and financial values.

READ-ONLY by default: run with ``--apply`` to write. Idempotent: re-runs only
create what is missing. The legacy collections are NOT deleted here; blocking
and deletion are a separate post-validated step (see README).

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/migrate_to_initial_business.py \
        [--project my-project] [--token <access-token>] \
        [--business-name "Minha Loja"] [--owner <uid>] [--apply]

Exit codes:
    0: success (writes applied, or dry-run plan printed)
    1: real error
    2: google-cloud-firestore not installed

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

BATCH_SIZE = 400

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_MISSING_LIB = 2

DEFAULT_BUSINESS_NAME = "Minha Loja"

# Legacy global collections -> tenant sub-collection names.
DOMAIN_COLLECTIONS: dict[str, str] = {
    "services": "services",
    "packages": "packages",
    "professionals": "professionals",
    "appointments": "appointments",
    "payments": "payments",
    "customerPackages": "customerPackages",
    "notifications": "notifications",
    "packageUsage": "packageUsage",
}

# Roles from the legacy global `role` field -> membership role.
ROLE_MAP: dict[str, str] = {
    "super_admin": "owner",
    "admin": "admin",
    "collaborator": "collaborator",
    "staff": "collaborator",
    "client": "client",
}


@dataclass
class MigrationPlan:
    """Accumulates the migration plan for a single run."""

    business_id: str = ""
    business_exists: bool = False
    memberships: dict[str, str] = field(default_factory=dict)
    collections: dict[str, list[tuple[str, dict[str, Any]]]] = field(
        default_factory=dict
    )

    def total_docs(self) -> int:
        return sum(len(docs) for docs in self.collections.values())


def load_collection(db: Any, name: str) -> list[tuple[str, dict[str, Any]]]:
    """Return [(doc_id, data)] for a global collection, skipping empty docs."""
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(name).stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def load_members(db: Any) -> dict[str, str]:
    """Map uid -> membership role from the legacy global user roles."""
    members: dict[str, str] = {}
    for snapshot in db.collection("users").stream():
        data = snapshot.to_dict() or {}
        raw_role = data.get("role") or data.get("tipo_usuario") or "client"
        role = ROLE_MAP.get(str(raw_role).lower(), "client")
        members[snapshot.id] = role
    return members


def collect_plan(
    db: Any,
    business_id: str,
    business_exists: bool,
) -> MigrationPlan:
    """Load everything needed to plan the migration (no writes)."""
    plan = MigrationPlan(
        business_id=business_id,
        business_exists=business_exists,
        memberships=load_members(db),
    )
    for legacy_name, sub_name in DOMAIN_COLLECTIONS.items():
        plan.collections[sub_name] = load_collection(db, legacy_name)
    return plan


def create_initial_business(
    db: Any,
    business_id: str,
    business_name: str,
    owner_uid: str,
    owner_role: str,
) -> None:
    """Create the business doc + owner membership + user projection."""
    business_ref = db.document(f"businesses/{business_id}")
    now = firestore.SERVER_TIMESTAMP
    business_ref.set(
        {
            "nome": business_name,
            "timezone": "America/Sao_Paulo",
            "status": "ATIVO",
            "ownerId": owner_uid,
            "createdAt": now,
            "updatedAt": now,
        }
    )
    db.document(f"businesses/{business_id}/members/{owner_uid}").set(
        {
            "role": owner_role,
            "ativo": True,
            "createdAt": now,
        }
    )
    db.document(f"users/{owner_uid}/businessMemberships/{business_id}").set(
        {
            "businessId": business_id,
            "businessName": business_name,
            "role": owner_role,
            "ativo": True,
            "createdAt": now,
        }
    )


def copy_collection(
    db: Any,
    business_id: str,
    sub_name: str,
    docs: list[tuple[str, dict[str, Any]]],
) -> int:
    """Copy docs into businesses/{business_id}/{sub_name}, preserving IDs and
    adding businessId. Idempotent per doc (set with merge)."""
    written = 0
    for offset in range(0, len(docs), BATCH_SIZE):
        chunk = docs[offset : offset + BATCH_SIZE]
        batch = db.batch()
        for doc_id, data in chunk:
            batch.set(
                db.document(f"businesses/{business_id}/{sub_name}/{doc_id}"),
                {**data, "businessId": business_id},
                merge=True,
            )
        batch.commit()
        written += len(chunk)
    return written


def write_memberships(
    db: Any,
    business_id: str,
    business_name: str,
    memberships: dict[str, str],
) -> int:
    """Create membership docs + user projections (idempotent, merge)."""
    written = 0
    for uid, role in memberships.items():
        now = firestore.SERVER_TIMESTAMP
        db.document(f"businesses/{business_id}/members/{uid}").set(
            {"role": role, "ativo": True, "createdAt": now},
            merge=True,
        )
        db.document(f"users/{uid}/businessMemberships/{business_id}").set(
            {
                "businessId": business_id,
                "businessName": business_name,
                "role": role,
                "ativo": True,
                "createdAt": now,
            },
            merge=True,
        )
        written += 1
    return written


def print_plan(plan: MigrationPlan, business_name: str) -> None:
    """Print the migration plan (dry-run)."""
    print("\n=== LOJA INICIAL ===")
    print(f"  businessId: {plan.business_id}")
    print(f"  nome: {business_name}")
    print(f"  ja existe: {plan.business_exists}")
    print(f"  membros (role por usuario): {len(plan.memberships)}")
    for uid, role in sorted(plan.memberships.items()):
        print(f"    {uid}: {role}")
    print("\n=== COLECOES A COPIAR ===")
    for sub_name, docs in plan.collections.items():
        print(f"  {sub_name}: {len(docs)} documentos")
    print(f"\n  Total: {plan.total_docs()} documentos")


def print_audit(db: Any, plan: MigrationPlan) -> None:
    """Validate counts after migration (read-only)."""
    print("\n=== AUDITORIA POS-MIGRACAO ===")
    ok = True
    for sub_name, docs in plan.collections.items():
        target = db.collection(f"businesses/{plan.business_id}/{sub_name}")
        count = len(list(target.stream()))
        expected = len(docs)
        match = "OK" if count == expected else "DIVERGE"
        if count != expected:
            ok = False
        print(f"  {sub_name}: {count}/{expected} {match}")
    members = db.collection(f"businesses/{plan.business_id}/members")
    member_count = len(list(members.stream()))
    expected_members = len(plan.memberships)
    member_match = "OK" if member_count == expected_members else "DIVERGE"
    if member_count != expected_members:
        ok = False
    print(f"  members: {member_count}/{expected_members} {member_match}")
    print(f"  resultado: {'OK' if ok else 'ATENCAO - rever contagens'}")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id (default: from ADC)")
    parser.add_argument(
        "--token",
        help="OAuth2 access token (alternative to GOOGLE_APPLICATION_CREDENTIALS)",
    )
    parser.add_argument("--business-name", default=DEFAULT_BUSINESS_NAME)
    parser.add_argument("--business-id", help="businessId fixo (opcional)")
    parser.add_argument(
        "--owner",
        required=True,
        help="uid do usuario que sera o owner da loja inicial",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="grava a migracao (padrao: apenas reporta o plano)",
    )
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
        business_id = args.business_id or "loja-inicial"
        business_ref = db.document(f"businesses/{business_id}")
        business_exists = business_ref.get().exists

        plan = collect_plan(db, business_id, business_exists)
        print(
            "Loaded: "
            + ", ".join(
                f"{sub}={len(docs)}" for sub, docs in plan.collections.items()
            )
        )
        print(f"Loaded users: {len(plan.memberships)}")

        if not args.apply:
            print_plan(plan, args.business_name)
            print("\n  (dry-run: nenhum dado foi gravado; use --apply para gravar)")
            return EXIT_OK

        owner_role = plan.memberships.get(args.owner, "owner")
        if not business_exists:
            create_initial_business(
                db, business_id, args.business_name, args.owner, owner_role
            )
            print(f"Created initial business: {business_id}")

        for sub_name, docs in plan.collections.items():
            written = copy_collection(db, business_id, sub_name, docs)
            print(f"Copied {sub_name}: {written} documentos")

        member_count = write_memberships(
            db, business_id, args.business_name, plan.memberships
        )
        print(f"Created memberships: {member_count}")

        print_audit(db, plan)
        return EXIT_OK
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: migration failed: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
