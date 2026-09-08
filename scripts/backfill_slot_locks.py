#!/usr/bin/env python3
"""Backfill appointmentSlots lock docs for existing future appointments.

Phase 5 data migration (Task 16). The slot-lock mechanism (Task 10) guards
against double-booking through `appointmentSlots/{professionalId}_{dayKey}_{timeKey}`
docs written by createAppointment. Appointments created BEFORE that mechanism
shipped carry no locks, so this script replays lock creation for every future
appointment (data_hora_fim > now) with status AGENDADO or CONFIRMADO.

Slot math mirrors functions/src/appointments/slot-keys.ts exactly:
30-minute slots from data_hora_inicio up to (but not including)
data_hora_fim, expressed in the business time zone (America/Sao_Paulo);
doc id = '{professionalId}_{YYYY-MM-DD}_{HH:MM}'; doc fields mirror
create-appointment.ts (professionalId, dayKey, timeKey, appointmentId,
createdAt as server timestamp).

The script NEVER writes partial data: all conflicts are detected BEFORE the
first write, and any conflict aborts the whole run (exit code 3). Existing
slot docs already owned by the same appointment are skipped (idempotent
re-runs are safe).

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python3 scripts/backfill_slot_locks.py [--project my-project] [--token <access-token>] [--dry-run]

Exit codes:
    0: success (locks written, or dry-run plan printed)
    1: real error (bad credentials, project not found, timezone unavailable, ...)
    2: google-cloud-firestore not installed
    3: slot conflict detected; no writes were performed

The Firestore emulator is used automatically when FIRESTORE_EMULATOR_HOST is set.
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

try:
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
except ImportError:  # pragma: no cover - import guard for dry-run checks
    firestore = None  # type: ignore[assignment]
    Credentials = None  # type: ignore[assignment]

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python < 3.9
    ZoneInfo = None  # type: ignore[assignment]

SLOT_MINUTES = 30
BUSINESS_TIME_ZONE = "America/Sao_Paulo"
STATUSES_IN_SCOPE = ("AGENDADO", "CONFIRMADO")
BATCH_SIZE = 400

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_MISSING_LIB = 2
EXIT_CONFLICT = 3


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

    candidates: list[tuple[str, dict[str, Any], datetime, datetime, str]] = field(
        default_factory=list
    )
    skipped: list[tuple[str, str]] = field(default_factory=list)
    plan: dict[str, dict[str, Any]] = field(default_factory=dict)
    conflicts: list[dict[str, Any]] = field(default_factory=list)
    existing_ok: int = 0


def load_collection(db: Any, name: str) -> list[tuple[str, dict[str, Any]]]:
    """Return [(doc_id, data)] for a collection, skipping empty docs."""
    docs: list[tuple[str, dict[str, Any]]] = []
    for snapshot in db.collection(name).stream():
        data = snapshot.to_dict()
        if data:
            docs.append((snapshot.id, data))
    return docs


def collect_candidates(
    appointments: list[tuple[str, dict[str, Any]]],
    result: BackfillResult,
) -> None:
    """Keep AGENDADO/CONFIRMADO appointments with a future, valid window."""
    now = datetime.now(timezone.utc)
    for doc_id, data in appointments:
        if data.get("status") not in STATUSES_IN_SCOPE:
            continue
        start = parse_timestamp(data.get("data_hora_inicio"))
        end = parse_timestamp(data.get("data_hora_fim"))
        professional_id = data.get("id_colaborador")
        if start is None or end is None:
            result.skipped.append((doc_id, "timestamp_invalido"))
            continue
        if end <= now:
            continue
        if end <= start:
            result.skipped.append((doc_id, "intervalo_invalido"))
            continue
        if not professional_id:
            result.skipped.append((doc_id, "sem_id_colaborador"))
            continue
        result.candidates.append((doc_id, data, start, end, str(professional_id)))


def slot_range(
    professional_id: str,
    start: datetime,
    end: datetime,
    zone: Any,
) -> list[tuple[str, str, str]]:
    """Mirror of slot-keys.ts slotRange: (doc_id, day_key, time_key) per slot.

    Iterates 30 minutes at a time from ``start`` up to (not including)
    ``end``; every slot keeps the dayKey of ``start``. Wall-clock values are
    expressed in the business time zone.
    """
    local_start = start.astimezone(zone)
    day_key = (
        f"{local_start.year:04d}-{local_start.month:02d}-{local_start.day:02d}"
    )
    slots: list[tuple[str, str, str]] = []
    cursor = start
    while cursor < end:
        local = cursor.astimezone(zone)
        time_key = f"{local.hour:02d}:{local.minute:02d}"
        doc_id = f"{professional_id}_{day_key}_{time_key}"
        slots.append((doc_id, day_key, time_key))
        cursor += timedelta(minutes=SLOT_MINUTES)
    return slots


def build_plan(result: BackfillResult, zone: Any) -> None:
    """Map every computed slot doc id to exactly one appointment.

    Two DIFFERENT appointments mapping to the same slot doc id is an overlap:
    the slot is recorded as a conflict and the run will abort.
    """
    for doc_id, _data, start, end, professional_id in result.candidates:
        for slot_doc_id, day_key, time_key in slot_range(
            professional_id, start, end, zone
        ):
            entry = result.plan.get(slot_doc_id)
            if entry is None:
                result.plan[slot_doc_id] = {
                    "appointment_id": doc_id,
                    "professional_id": professional_id,
                    "day_key": day_key,
                    "time_key": time_key,
                }
            elif entry["appointment_id"] != doc_id:
                result.conflicts.append(
                    {
                        "slot_doc_id": slot_doc_id,
                        "appointments": sorted(
                            {entry["appointment_id"], doc_id}
                        ),
                    }
                )


def check_existing(db: Any, result: BackfillResult) -> list[dict[str, Any]]:
    """Read the target slot docs; split plan into to-write vs already-owned.

    Returns a list of conflicts discovered against live data (slot doc exists
    but is owned by a different appointment, or has no appointmentId). The
    existing-owner case is skipped (idempotent), not written.
    """
    live_conflicts: list[dict[str, Any]] = []
    doc_ids = sorted(result.plan.keys())
    for offset in range(0, len(doc_ids), BATCH_SIZE):
        chunk = doc_ids[offset : offset + BATCH_SIZE]
        refs = [db.document(f"appointmentSlots/{doc_id}") for doc_id in chunk]
        for snapshot in db.get_all(refs):
            planned = result.plan[snapshot.id]
            if not snapshot.exists:
                continue
            existing = snapshot.to_dict() or {}
            owner = existing.get("appointmentId")
            if owner == planned["appointment_id"]:
                result.existing_ok += 1
                del result.plan[snapshot.id]
            else:
                live_conflicts.append(
                    {
                        "slot_doc_id": snapshot.id,
                        "appointments": sorted(
                            {str(owner) if owner is not None else "(sem dono)", planned["appointment_id"]}
                        ),
                    }
                )
    return live_conflicts


def write_plan(db: Any, plan: dict[str, dict[str, Any]]) -> int:
    """Write the planned slot docs in batches; returns the number written."""
    entries = sorted(plan.items(), key=lambda kv: kv[0])
    written = 0
    for offset in range(0, len(entries), BATCH_SIZE):
        chunk = entries[offset : offset + BATCH_SIZE]
        batch = db.batch()
        for slot_doc_id, entry in chunk:
            batch.set(
                db.document(f"appointmentSlots/{slot_doc_id}"),
                {
                    "professionalId": entry["professional_id"],
                    "dayKey": entry["day_key"],
                    "timeKey": entry["time_key"],
                    "appointmentId": entry["appointment_id"],
                    "createdAt": firestore.SERVER_TIMESTAMP,
                },
            )
        batch.commit()
        written += len(chunk)
    return written


def print_conflicts(conflicts: list[dict[str, Any]]) -> None:
    """Print overlapping slots with the conflicting appointments."""
    print("\n=== CONFLITOS DE SLOT ===")
    for item in conflicts:
        print(
            f"  slot {item['slot_doc_id']}: agendamentos "
            f"{item['appointments'][0]} e {item['appointments'][1]} mapeiam para o mesmo slot"
        )


def print_summary(result: BackfillResult, dry_run: bool, written: int) -> None:
    """Print the run summary."""
    print("\n=== RESUMO ===")
    print(f"  Agendamentos processados: {len(result.candidates)}")
    if dry_run:
        print(f"  Slots a criar: {len(result.plan)}")
    else:
        print(f"  Slots criados: {written}")
    print(f"  Slots ja existentes (mesmo agendamento): {result.existing_ok}")
    print(f"  Conflitos: {len(result.conflicts)}")
    if result.skipped:
        reasons: dict[str, int] = defaultdict(int)
        for _doc_id, reason in result.skipped:
            reasons[reason] += 1
        print(
            f"  Ignorados: {len(result.skipped)} "
            f"({', '.join(f'{k}: {v}' for k, v in sorted(reasons.items()))})"
        )
    if dry_run:
        print("  (dry-run: nenhum dado foi gravado)")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id (default: from ADC)")
    parser.add_argument(
        "--token",
        help="OAuth2 access token (alternative to GOOGLE_APPLICATION_CREDENTIALS)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="apenas reporta o plano, sem gravar nada",
    )
    args = parser.parse_args(argv)

    if firestore is None:
        print(
            "ERROR: google-cloud-firestore is not installed. "
            "Run: pip install google-cloud-firestore",
            file=sys.stderr,
        )
        return EXIT_MISSING_LIB
    if ZoneInfo is None:
        print(
            f"ERROR: zoneinfo (Python 3.9+) indisponivel; nao e possivel converter para {BUSINESS_TIME_ZONE}",
            file=sys.stderr,
        )
        return EXIT_ERROR
    try:
        zone = ZoneInfo(BUSINESS_TIME_ZONE)
    except Exception as exc:  # noqa: BLE001 - report any tz problem as fatal
        print(
            f"ERROR: fuso horario '{BUSINESS_TIME_ZONE}' indisponivel: {exc}",
            file=sys.stderr,
        )
        return EXIT_ERROR

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
        loaded = load_collection(db, "appointments")
        print(f"Loaded {len(loaded)} docs from 'appointments'")

        result = BackfillResult()
        collect_candidates(loaded, result)
        build_plan(result, zone)
        live_conflicts = check_existing(db, result)
        all_conflicts = result.conflicts + live_conflicts

        if all_conflicts:
            print_conflicts(all_conflicts)
            print("\nABORT: conflitos detectados; nenhum dado foi gravado.")
            return EXIT_CONFLICT

        written = 0
        if args.dry_run:
            print("\n=== PLANO (dry-run) ===")
            for slot_doc_id, entry in sorted(result.plan.items()):
                print(
                    f"  {slot_doc_id}: agendamento {entry['appointment_id']}"
                )
        elif result.plan:
            written = write_plan(db, result.plan)
            print(f"Written {written} slot docs")

        print_summary(result, args.dry_run, written)
        return EXIT_OK
    except Exception as exc:  # noqa: BLE001 - real errors must exit non-zero
        print(f"ERROR: backfill failed: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
