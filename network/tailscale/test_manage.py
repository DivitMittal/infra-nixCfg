"""Exercise adoption, saved-plan and credential handoff failure boundaries."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("tailnet_manage", Path(__file__).with_name("manage.py"))
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


class TailnetOperations(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.configuration = self.root / "config.json"
        self.configuration.write_text("{}")
        self.environment = patch.dict(os.environ, {
            "TAILSCALE_TAILNET": "test.invalid",
            "TF_VAR_state_passphrase": "test-passphrase-is-at-least-32-characters",
            "XDG_STATE_HOME": str(self.root),
            "TAILSCALE_TF_CONFIG": str(self.configuration),
            "TAILSCALE_TF_LOCK": str(self.configuration),
        }, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def run_mode(self, mode):
        with patch.object(manage.sys, "argv", ["tailscale-personal", mode]):
            manage.main()

    def state_directory(self):
        return next((self.root / "infra-nixCfg/tofu/tailscale").iterdir())

    def prepare_plan(self):
        with patch.object(manage.subprocess, "run"):
            self.run_mode("init")
        directory = self.state_directory()
        (directory / "policy-baseline.json").write_text('{"groups": {"group:existing": []}}')
        (directory / "reviewed.tfplan").write_text("older plan")
        return directory

    def test_missing_tailnet_does_not_create_state(self):
        del os.environ["TAILSCALE_TAILNET"]
        with self.assertRaisesRegex(RuntimeError, "TAILSCALE_TAILNET"):
            self.run_mode("init")
        self.assertFalse((self.root / "infra-nixCfg").exists())

    def test_existing_snapshot_is_never_overwritten(self):
        target = self.root / "policy-baseline.json"
        target.write_text("preserve existing policy")
        with patch.object(manage, "request") as request:
            with self.assertRaisesRegex(RuntimeError, "baseline exists"):
                manage.snapshot(self.root, "test.invalid")
        request.assert_not_called()
        self.assertEqual(target.read_text(), "preserve existing policy")

    def test_invalid_snapshot_does_not_create_baseline(self):
        with patch.object(manage, "api_headers", return_value={}), patch.object(manage, "request", return_value=[]):
            with self.assertRaisesRegex(RuntimeError, "JSON policy object"):
                manage.snapshot(self.root, "test.invalid")
        self.assertFalse((self.root / "policy-baseline.json").exists())

    def test_failed_plan_removes_previous_saved_plan(self):
        directory = self.prepare_plan()
        with patch.object(manage.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["tofu", "plan"])):
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_mode("plan")
        self.assertFalse((directory / "reviewed.tfplan").exists())

    def test_failed_apply_invalidates_saved_plan(self):
        directory = self.prepare_plan()
        with patch.object(manage.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["tofu", "apply"])):
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_mode("apply")
        self.assertFalse((directory / "reviewed.tfplan").exists())

    def test_distinct_tailnets_use_distinct_private_directories(self):
        with patch.object(manage.subprocess, "run"):
            self.run_mode("init")
            os.environ["TAILSCALE_TAILNET"] = "other.invalid"
            self.run_mode("init")
        directories = list((self.root / "infra-nixCfg/tofu/tailscale").iterdir())
        self.assertEqual(len(directories), 2)
        self.assertTrue(all(d.stat().st_mode & 0o777 == 0o700 for d in directories))

    def test_export_encrypts_via_stdin_and_does_not_log_values(self):
        os.environ["TAILSCALE_AGE_RECIPIENT"] = "test-recipient"
        os.environ["TAILSCALE_SECRETS_DIR"] = str(self.root / "secrets")
        values = {name: {"value": "sensitive-" + name} for name in ("ci_client_id", "ci_client_secret", "t1_auth_key")}
        calls = []

        def run(args, **kwargs):
            calls.append((args, kwargs))
            if args[0] == "tofu":
                return subprocess.CompletedProcess(args, 0, json.dumps(values).encode())
            return subprocess.CompletedProcess(args, 0, b"age-encrypted-fixture")

        output = io.StringIO()
        with patch.object(manage.subprocess, "run", side_effect=run), contextlib.redirect_stdout(output):
            manage.export_secrets(self.root)
        self.assertNotIn("sensitive-", output.getvalue())
        self.assertTrue(all("sensitive-" not in str(args) for args, _ in calls))
        self.assertEqual(len(list((self.root / "secrets").rglob("*.age"))), 2)
        self.assertTrue(all(p.read_bytes() == b"age-encrypted-fixture" for p in (self.root / "secrets").rglob("*.age")))
        self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in (self.root / "secrets").rglob("*.age")))


    def test_existing_router_key_does_not_block_ci_export(self):
        os.environ["TAILSCALE_AGE_RECIPIENT"] = "test-recipient"
        os.environ["TAILSCALE_SECRETS_DIR"] = str(self.root / "secrets")
        router = self.root / "secrets/homelab/T1-tailscale.age"
        router.parent.mkdir(parents=True)
        router.write_text("preserve enrolled router")
        values = {name: {"value": "test-value"} for name in ("ci_client_id", "ci_client_secret")}
        results = [subprocess.CompletedProcess([], 0, json.dumps(values).encode())]
        results.extend(subprocess.CompletedProcess([], 0, b"encrypted") for _ in range(2))
        with patch.object(manage.subprocess, "run", side_effect=results), contextlib.redirect_stdout(io.StringIO()):
            manage.export_secrets(self.root)
        self.assertEqual(router.read_text(), "preserve enrolled router")

    def test_router_export_never_replaces_existing_enrollment(self):
        os.environ["TAILSCALE_AGE_RECIPIENT"] = "test-recipient"
        os.environ["TAILSCALE_SECRETS_DIR"] = str(self.root / "secrets")
        router = self.root / "secrets/homelab/T1-tailscale.age"
        router.parent.mkdir(parents=True)
        router.write_text("preserve enrolled router")
        result = subprocess.CompletedProcess([], 0, b"{}")
        with patch.object(manage.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "already exists"):
                manage.export_secrets(self.root, router_only=True)
        self.assertEqual(router.read_text(), "preserve enrolled router")


if __name__ == "__main__":
    unittest.main()
