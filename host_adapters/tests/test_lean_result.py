"""New mechanical decoder controls; LOGOS policy has separate source controls."""
import json
import unittest
from host_adapters.lean_result import (
    STAGES, decode_import_result, decode_replay_receipt,
    lean_import_policy_arguments, lean_replay_policy_arguments,
)

D = "a" * 64


def report():
    return {"schema": "logos-lean-result/1", "outcome": "verified",
            "stages": dict.fromkeys(STAGES, "passed"),
            "target": {"lean": "T.example", "logos": "T.example"}, "assumptions": [],
            "information_losses": [], "diagnostics": [], "audit": None,
            "package": {"path": "/private/job/package", "manifest_sha256": D}}


def receipt():
    stages = {name: {"status": "passed", "code": None, "detail": "checked"} for name in STAGES}
    stages["lean_accepted"]["status"] = "not_run"
    return {"schema": "logos-lean-replay/1", "replayed": True, "verified": False,
            "manifest_sha256": D, "stages": stages, "trusted_base": []}


def wire(value):
    return json.dumps(value).encode()


class LeanResultDecoderTests(unittest.TestCase):
    def test_current_shapes_preserved(self):
        self.assertEqual(decode_import_result(wire(report())), report())
        self.assertEqual(decode_replay_receipt(wire(receipt())), receipt())

    def test_early_refusal_has_nullable_logos_target(self):
        value = report()
        value["outcome"] = "invalid_source"
        value["target"]["logos"] = None
        value["package"] = None
        value["stages"] = dict.fromkeys(STAGES, "not_run")
        self.assertEqual(decode_import_result(wire(value)), value)
        args = lean_import_policy_arguments(wire(value), exit_code=1,
            expected_lean="T.example", expected_logos=None,
            expected_package_path="/private/job/package", observed_manifest_sha256=None,
            observed_package_schema=None)
        self.assertEqual(args[6], "-")
        self.assertEqual(args[8], "-")

    def test_contradiction_is_preserved_for_logos(self):
        value = report()
        value["stages"]["independent_recheck"] = "not_run"
        value["assumptions"] = ["sorryAx"]
        self.assertEqual(decode_import_result(wire(value)), value)
        replay = receipt()
        replay["verified"] = True
        self.assertTrue(decode_replay_receipt(wire(replay))["verified"])

    def test_duplicate_unknown_and_legacy_schemas(self):
        payload = wire(report())
        with self.assertRaises(ValueError):
            decode_import_result(payload[:-1] + b',"schema":"logos-lean-result/1"}')
        for schema in ("logos-lean-result/2", "macsad-proof-demo/1"):
            value = report()
            value["schema"] = schema
            with self.assertRaises(ValueError):
                decode_import_result(wire(value))
        value = receipt()
        value["schema"] = "logos-lean-replay/2"
        with self.assertRaises(ValueError):
            decode_replay_receipt(wire(value))

    def test_wrong_types_missing_stages_and_extra_fields(self):
        invalid = []
        value = report(); del value["stages"]["independent_recheck"]; invalid.append(value)
        value = report(); value["stages"]["fresh_replay"] = True; invalid.append(value)
        value = report(); value["package"]["manifest_sha256"] = "A" * 64; invalid.append(value)
        value = report(); value["unknown"] = 1; invalid.append(value)
        value = report(); value["assumptions"] = "propext"; invalid.append(value)
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                decode_import_result(wire(value))
        value = receipt(); value["replayed"] = 1
        with self.assertRaises(ValueError):
            decode_replay_receipt(wire(value))

    def test_unicode_depth_nonfinite_and_trailing_json(self):
        for payload in (wire(report()) + b'{}', b'{"x":NaN}', b'[' * 65 + b'0' + b']' * 65, b'\xff'):
            with self.subTest(payload=payload[:32]), self.assertRaises(ValueError):
                decode_import_result(payload)
        value = report(); value["target"]["lean"] = "\ud800"
        with self.assertRaises(ValueError):
            decode_import_result(wire(value))

    def test_framing_carries_observed_identity_separately(self):
        args = lean_import_policy_arguments(wire(report()), exit_code=0,
            expected_lean="Other.target", expected_logos="T.example",
            expected_package_path="/private/job/package", observed_manifest_sha256="b" * 64,
            observed_package_schema="logos-lean-package/1")
        self.assertEqual(len(args), 18)
        self.assertEqual(args[0], "macsad-lean-facts/1")
        facts = [bytes.fromhex(item).decode() if item != "-" else "" for item in args[1:]]
        self.assertEqual(facts[4], "T.example")
        self.assertEqual(facts[6], "Other.target")
        self.assertEqual(facts[10], D)
        self.assertEqual(facts[11], "b" * 64)

    def test_replay_framing_does_not_inherit_original_acceptance(self):
        args = lean_replay_policy_arguments(wire(receipt()), exit_code=0, expected_manifest_sha256=D)
        facts = [bytes.fromhex(item).decode() if item != "-" else "" for item in args[1:]]
        self.assertEqual(facts[3], "not_run,passed,passed,passed,passed,passed,passed")
        self.assertEqual(facts[15:], ["1", "0"])


if __name__ == "__main__":
    unittest.main()
