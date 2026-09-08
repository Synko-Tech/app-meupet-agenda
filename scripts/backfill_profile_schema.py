#!/usr/bin/env python3
"""Backfill `schemaVersion` on completed legacy user profiles.

After the CPF/address feature, profiles completed by the callable
`completeOwnProfile` carry `profileComplete: true` and `schemaVersion: 2` on
`users/{uid}`. Completed profiles written before that field existed (or
written by seeds/tools with an older value) miss the version stamp, so this
migration aligns them BEFORE the audit starts flagging the inconsistency.

Migration rules (never violated):

- The script NEVER invents CPF or address: it only stamps `schemaVersion` on
  users already marked `profileComplete: true`. Users whose
  `profileComplete` is missing or false are only COUNTED in the report — they
  stay incomplete until the user completes the form (CompleteProfileScreen).
- Dry-run by default; writes only with `--apply`.
- Idempotent: re-running after `--apply` finds nothing to change.
- `userPrivate/{uid}` is never read, so no CPF value can ever reach the
  output; the report prints only counts and document ids.

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/backfill_profile_schema.py [--project my-project] [--token <access-token>] [--apply]

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
from typing import Any, Optional

try:
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
except ImportError:  # pragma: no cover - import guard for dry-run checks
    firestore = None  # type: ignore[assignment]
    Credentials = None  # type: ignore[assignment]

PROFILE_SCHEMA_VERSION = 2
BATCH_SIZE = 400

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_MISSING_LIB = 2


@dataclass
class BackfillResult:
    """Accumulates the backfill plan for a single run."""

    ok: int = 0
    schema_mismatch: list[str] = field(default_factory=list)
    incomplete: list[str] = field(default_factory=list)


def analyze_users(db: Any) -> BackfillResult:
    """Classify every `users/{uid}` doc by profile/schema state.

    Only the `users` collection is streamed — `userPrivate` (CPF/address) is
    never read, keeping the script free of PII by construction.
    """
    result = BackfillResult()
    for snapshot in db.collection("users").stream():
        data = snapshot.to_dict() or {}
        if data.get("profileComplete") is not True:
            result.incomplete.append(snapshot.id)
            continue
        if data.get("schemaVersion") != PROFILE_SCHEMA_VERSION:
            result.schema_mismatch.append(snapshot.id)
        else:
            result.ok += 1
    return result


def write_updates(db: Any, candidates: list[str], batch_size: int = BATCH_SIZE) -> int:
    """Stamp `schemaVersion` on the given user docs; returns the number written."""
    written = 0
    for offset in range(0, len(candidates), batch_size):
        for uid in candidates[offset : offset + batch_size]:
            db.document(f"users/{uid}").update(
                {"schemaVersion": PROFILE_SCHEMA_VERSION},
            )
            written += 1
    return written


def run(db: Any, apply: bool) -> int:
    """Analyze, report and (with ``apply``) write; returns the exit code."""
    result = analyze_users(db)
    loaded = result.ok + len(result.schema_mismatch) + len(result.incomplete)
    print(f"Loaded users: {loaded}")

    written = 0
    if not apply:
        print("\n=== PLANO (dry-run) ===")
        for uid in sorted(result.schema_mismatch):
            print(f"  users/{uid}: schemaVersion <- {PROFILE_SCHEMA_VERSION}")
    else:
        written = write_updates(db, sorted(result.schema_mismatch))
        print(f"Written {written} user updates")

    print("\n=== RESUMO ===")
    print(f"  Perfis completos e consistentes: {result.ok}")
    print(f"  Inconsistencias de schema (perfis completos): {len(result.schema_mismatch)}")
    print(f"  Perfis incompletos (aguardam o usuario, nao alterados): {len(result.incomplete)}")
    if not apply:
        print("  (dry-run: nenhum dado foi gravado; use --apply para gravar)")
    else:
        print(f"  Usuarios atualizados: {written}")
    return EXIT_OK


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
        return run(db, args.apply)
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: backfill failed: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
