#!/usr/bin/env python3
"""Backfill `createdAt` on legacy `payments` docs.

The period filter (allPaymentsStream / customerPaymentsStream) queries
`payments.createdAt` server-side. Documents created before that field was
introduced have no `createdAt` and would never appear in a period query, so
this migration fills the gap BEFORE the server-side filter ships.

Source priority per payment (never overwrites an existing `createdAt`):
    1. `createdAt` (already present -> skipped)
    2. `paidAt`
    3. `data_pagamento`
    4. document `createTime` (recovered from the document snapshot metadata)

The script NEVER writes partial data in `--apply` mode beyond the chosen
batches, is idempotent (re-runs only fill remaining docs), and defaults to
`--dry-run` so the plan can be reviewed first.

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/backfill_payment_created_at.py [--project my-project] [--token <access-token>] [--apply]

Exit codes:
    0: success (writes applied, or dry-run plan printed)
    1: real error (bad credentials, project not found, ...)
    2: google-cloud-firestore not installed

The Firestore emulator is used automatically when FIRESTORE_EMULATOR_HOST is set.
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

BATCH_SIZE = 400

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_MISSING_LIB = 2


def parse_timestamp(value: Any) -> Optional[datetime]:
    """Convert a Firestore timestamp value to an aware UTC datetime.

    Mirrors scripts/audit_firestore.py: aware datetimes pass through, naive
    datetimes are assumed UTC, ISO strings are parsed, and protobuf Timestamp
    objects fall back to ``ToDatetime()``.
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


@dataclass
class BackfillResult:
    """Accumulates the backfill plan for a single run."""

    candidates: list[tuple[str, datetime, str]] = field(default_factory=list)
    skipped_existing: int = 0
    skipped_no_source: int = 0


def collect_candidates(db: Any) -> BackfillResult:
    """Keep payments without `createdAt` and pick the source timestamp.

    Priority: `paidAt` -> `data_pagamento` -> document createTime.
    """
    result = BackfillResult()
    for snapshot in db.collection("payments").stream():
        doc_id = snapshot.id
        data = snapshot.to_dict() or {}
        if parse_timestamp(data.get("createdAt")) is not None:
            result.skipped_existing += 1
            continue
        source = parse_timestamp(data.get("paidAt"))
        source_name = "paidAt"
        if source is None:
            source = parse_timestamp(data.get("data_pagamento"))
            source_name = "data_pagamento"
        if source is None:
            create_time = getattr(snapshot, "create_time", None)
            source = parse_timestamp(create_time)
            source_name = "createTime"
        if source is None:
            result.skipped_no_source += 1
            continue
        result.candidates.append((doc_id, source, source_name))
    return result


def write_updates(db: Any, candidates: list[tuple[str, datetime, str]]) -> int:
    """Write `createdAt` in batches; returns the number written."""
    written = 0
    for offset in range(0, len(candidates), BATCH_SIZE):
        chunk = candidates[offset : offset + BATCH_SIZE]
        batch = db.batch()
        for doc_id, created_at, _source in chunk:
            batch.update(
                db.document(f"payments/{doc_id}"),
                {"createdAt": created_at},
            )
        batch.commit()
        written += len(chunk)
    return written


def print_summary(result: BackfillResult, dry_run: bool, written: int) -> None:
    """Print the run summary."""
    print("\n=== RESUMO ===")
    print(f"  Pagamentos sem createdAt a migrar: {len(result.candidates)}")
    if dry_run:
        print(f"  Pagamentos a atualizar: {len(result.candidates)}")
    else:
        print(f"  Pagamentos atualizados: {written}")
    print(f"  Pagamentos com createdAt (ignorados): {result.skipped_existing}")
    print(f"  Pagamentos sem fonte de data (ignorados): {result.skipped_no_source}")
    if dry_run:
        print("  (dry-run: nenhum dado foi gravado; use --apply para gravar)")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id (default: from ADC)")
    parser.add_argument(
        "--token",
        help="OAuth2 access token (alternative to GOOGLE_APPLICATION_CREDENTIALS)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="grava os updates (padrao: apenas reporta o plano)",
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
        result = collect_candidates(db)
        print(f"Loaded payments: {result.skipped_existing + result.skipped_no_source + len(result.candidates)}")

        if not args.apply:
            print("\n=== PLANO (dry-run) ===")
            for doc_id, created_at, source in sorted(
                result.candidates, key=lambda item: item[1]
            ):
                print(
                    f"  payments/{doc_id}: createdAt <- {created_at.isoformat()} "
                    f"(fonte: {source})"
                )
            written = 0
        else:
            written = write_updates(db, result.candidates)
            print(f"Written {written} payment updates")

        print_summary(result, not args.apply, written)
        return EXIT_OK
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: backfill failed: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
