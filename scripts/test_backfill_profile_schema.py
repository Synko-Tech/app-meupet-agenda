#!/usr/bin/env python3
"""Unit tests for scripts/backfill_profile_schema.py.

Uses a stateful fake Firestore client (no google-cloud-firestore required),
mirroring the script's contract: `analyze_users(db)` / `write_updates(db, ...)`
take the client as a parameter.

Run:
    python3 -m unittest scripts.test_backfill_profile_schema -v
or:
    python3 -m unittest discover -s scripts -p "test_*.py" -v
"""

from __future__ import annotations

import contextlib
import io
import re
import unittest
from typing import Any

from backfill_profile_schema import (
    BackfillResult,
    analyze_users,
    run,
    write_updates,
)


class FakeSnapshot:
    def __init__(self, doc_id: str, data: dict[str, Any]) -> None:
        self.id = doc_id
        self._data = data

    def to_dict(self) -> dict[str, Any]:
        return dict(self._data)


class FakeDb:
    """Stateful fake of google.cloud.firestore.Client over a `users` dict."""

    def __init__(self, users: dict[str, dict[str, Any]]) -> None:
        self._docs = {uid: dict(data) for uid, data in users.items()}
        self.accessed: list[str] = []
        self.updates: list[tuple[str, dict[str, Any]]] = []

    def collection(self, name: str) -> "FakeDb":
        if name != "users":
            raise AssertionError(f"script must never touch collection {name!r}")
        self.accessed.append(name)
        return self

    def stream(self) -> list[FakeSnapshot]:
        return [FakeSnapshot(uid, data) for uid, data in sorted(self._docs.items())]

    def document(self, path: str) -> "FakeRef":
        assert path.startswith("users/"), f"unexpected document path {path!r}"
        return FakeRef(self, path.split("/", 1)[1])


class FakeRef:
    def __init__(self, db: FakeDb, uid: str) -> None:
        self._db = db
        self._uid = uid

    def update(self, patch: dict[str, Any]) -> None:
        if self._uid not in self._db._docs:
            raise KeyError(f"no doc users/{self._uid}")
        self._db._docs[self._uid].update(patch)
        self._db.updates.append((f"users/{self._uid}", dict(patch)))


COMPLETED = {"nome": "Alice", "email": "alice@x.com", "profileComplete": True, "schemaVersion": 2}
MISMATCH = {"nome": "Bob", "email": "bob@x.com", "profileComplete": True, "schemaVersion": 0}
MISSING_VERSION = {"nome": "Carol", "email": "carol@x.com", "profileComplete": True}
INCOMPLETE = {"nome": "Dan", "email": "dan@x.com", "profileComplete": False}
NO_FLAG = {"nome": "Eve", "email": "eve@x.com"}


def run_script(db: FakeDb, apply: bool) -> str:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = run(db, apply=apply)
    assert code == 0, f"run() returned {code}"
    return out.getvalue()


class AnalyzeUsersTests(unittest.TestCase):
    def test_classifies_all_states(self) -> None:
        db = FakeDb(
            {
                "u_completed": dict(COMPLETED),
                "u_mismatch": dict(MISMATCH),
                "u_missing_version": dict(MISSING_VERSION),
                "u_incomplete": dict(INCOMPLETE),
                "u_no_flag": dict(NO_FLAG),
            }
        )
        result = analyze_users(db)
        self.assertIsInstance(result, BackfillResult)
        self.assertEqual(result.ok, 1)
        self.assertEqual(sorted(result.schema_mismatch), ["u_mismatch", "u_missing_version"])
        self.assertEqual(sorted(result.incomplete), ["u_incomplete", "u_no_flag"])
        self.assertEqual(db.accessed, ["users"])
        self.assertEqual(db.updates, [])

    def test_never_reads_user_private(self) -> None:
        db = FakeDb({"u_incomplete": dict(NO_FLAG)})
        with self.assertRaises(AssertionError):
            db.collection("userPrivate").stream()
        analyze_users(db)  # analysis itself only streams `users`
        self.assertEqual(db.accessed, ["users"])


class DryRunTests(unittest.TestCase):
    def test_dry_run_writes_nothing(self) -> None:
        db = FakeDb(
            {
                "u_mismatch": dict(MISMATCH),
                "u_incomplete": dict(NO_FLAG),
            }
        )
        output = run_script(db, apply=False)
        self.assertEqual(db.updates, [])
        self.assertIn("PLANO (dry-run)", output)
        self.assertIn("users/u_mismatch", output)
        self.assertIn("Inconsistencias de schema (perfis completos): 1", output)
        self.assertIn("Perfis incompletos (aguardam o usuario, nao alterados): 1", output)

    def test_dry_run_clean_db_is_noop(self) -> None:
        db = FakeDb({"u_completed": dict(COMPLETED)})
        output = run_script(db, apply=False)
        self.assertEqual(db.updates, [])
        self.assertIn("Inconsistencias de schema (perfis completos): 0", output)


class ApplyTests(unittest.TestCase):
    def test_apply_writes_only_schema_version(self) -> None:
        db = FakeDb(
            {
                "u_completed": dict(COMPLETED),
                "u_mismatch": dict(MISMATCH),
                "u_missing_version": dict(MISSING_VERSION),
                "u_incomplete": dict(NO_FLAG),
            }
        )
        output = run_script(db, apply=True)
        self.assertEqual(
            db.updates,
            [
                ("users/u_mismatch", {"schemaVersion": 2}),
                ("users/u_missing_version", {"schemaVersion": 2}),
            ],
        )
        # Incomplete profiles are reported but never written.
        self.assertEqual(db._docs["u_incomplete"], NO_FLAG)
        self.assertIn("Usuarios atualizados: 2", output)
        self.assertIn("Perfis incompletos (aguardam o usuario, nao alterados): 1", output)

    def test_apply_second_run_is_noop(self) -> None:
        db = FakeDb(
            {
                "u_mismatch": dict(MISMATCH),
                "u_missing_version": dict(MISSING_VERSION),
            }
        )
        run_script(db, apply=True)
        first_writes = len(db.updates)
        output = run_script(db, apply=True)
        self.assertEqual(len(db.updates), first_writes)
        self.assertIn("Usuarios atualizados: 0", output)
        self.assertIn("Inconsistencias de schema (perfis completos): 0", output)
        self.assertEqual(db._docs["u_mismatch"]["schemaVersion"], 2)


class NoPiiTests(unittest.TestCase):
    def test_output_never_contains_full_cpf(self) -> None:
        cpf = "12345678901"
        # Even if a user doc carried a raw cpf field (defensive: scripts never
        # read userPrivate, but a doc with such a field must not leak it).
        db = FakeDb(
            {
                "u_mismatch": dict(MISMATCH),
                "u_incomplete": {"nome": "Dan", "cpf": cpf},
            }
        )
        for apply in (False, True):
            output = run_script(db, apply=apply)
            self.assertNotIn(cpf, output)
            self.assertIsNone(re.search(r"\d{11}", output))


class WriteUpdatesTests(unittest.TestCase):
    def test_batches_writes(self) -> None:
        users = {f"u{i}": dict(MISMATCH) for i in range(3)}
        db = FakeDb(users)
        candidates = sorted(analyze_users(db).schema_mismatch)
        written = write_updates(db, candidates, batch_size=2)
        self.assertEqual(written, 3)
        self.assertEqual(len(db.updates), 3)
        self.assertTrue(all(u["schemaVersion"] == 2 for u in db._docs.values()))


if __name__ == "__main__":
    unittest.main()
