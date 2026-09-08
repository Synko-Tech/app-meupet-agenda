#!/usr/bin/env python3
"""Unit tests for the profile-schema checks added to scripts/audit_firestore.py.

The new checks are pure functions (`check_profile_schema(users, result)`) so
they are tested without a Firestore client.

Run:
    python3 -m unittest scripts.test_audit_firestore -v
"""

from __future__ import annotations

import re
import unittest

from audit_firestore import AuditResult, check_profile_schema


def run_check(users: list[tuple[str, dict]]) -> AuditResult:
    result = AuditResult()
    check_profile_schema(users, result)
    return result


def findings_of(result: AuditResult, check: str) -> list[dict]:
    return [f for f in result.findings if f["check"] == check]


class CheckProfileSchemaTests(unittest.TestCase):
    def test_counts_incomplete_profiles(self) -> None:
        users = [
            ("u_missing_flag", {"role": "client"}),  # profileComplete absent
            ("u_false", {"role": "client", "profileComplete": False}),
            ("u_completed", {"role": "client", "profileComplete": True, "schemaVersion": 2}),
        ]
        result = run_check(users)
        incomplete = findings_of(result, "incomplete_profile")
        self.assertEqual(sorted(f["id"] for f in incomplete), ["u_false", "u_missing_flag"])
        self.assertEqual(findings_of(result, "profile_schema_mismatch"), [])

    def test_flags_schema_inconsistencies_on_completed_profiles(self) -> None:
        users = [
            ("u_no_version", {"profileComplete": True}),
            ("u_old_version", {"profileComplete": True, "schemaVersion": 1}),
            ("u_string_version", {"profileComplete": True, "schemaVersion": "2"}),
            ("u_ok", {"profileComplete": True, "schemaVersion": 2}),
        ]
        result = run_check(users)
        mismatches = findings_of(result, "profile_schema_mismatch")
        self.assertEqual(
            sorted(f["id"] for f in mismatches),
            ["u_no_version", "u_old_version", "u_string_version"],
        )

    def test_incomplete_profiles_are_not_schema_mismatches(self) -> None:
        users = [
            ("u_no_flag", {"profileComplete": False, "schemaVersion": 0}),
            ("u_no_flag2", {}),
        ]
        result = run_check(users)
        self.assertEqual(findings_of(result, "profile_schema_mismatch"), [])
        self.assertEqual(
            len(findings_of(result, "incomplete_profile")),
            2,
        )

    def test_findings_never_carry_cpf_or_11_digit_values(self) -> None:
        users = [
            ("u_completed", {"profileComplete": True, "schemaVersion": 1}),
            ("u_incomplete", {"role": "client", "cpf": "12345678901"}),
        ]
        result = run_check(users)
        payload = repr(result.findings)
        self.assertNotIn("12345678901", payload)
        self.assertNotIn("cpf", payload)
        self.assertIsNone(re.search(r"\d{11}", payload))

    def test_incomplete_finding_carries_role_only(self) -> None:
        users = [("u_x", {"nome": "Alice", "email": "alice@x.com", "role": "client"})]
        result = run_check(users)
        (finding,) = findings_of(result, "incomplete_profile")
        self.assertEqual(finding["id"], "u_x")
        self.assertEqual(finding["role"], "client")
        self.assertNotIn("nome", finding)
        self.assertNotIn("email", finding)


if __name__ == "__main__":
    unittest.main()
