"""Verify that a failed test reaches independent review and drives a scoped repair."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import test_supervisor


class SupervisorRepairTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="kakao-supervisor-test-")
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name)
        self.run, self.root = base / "run", base / "checkout"
        self.run.mkdir()
        self.root.mkdir()

        def git_command(_root, *args):
            return "base-commit\n" if args[0] == "rev-parse" else ""

        git = patch.object(test_supervisor, "git", side_effect=git_command)
        digest = patch.object(test_supervisor, "source_digest", return_value="current-source")
        git.start()
        digest.start()
        self.addCleanup(git.stop)
        self.addCleanup(digest.stop)
        self.supervisor = test_supervisor.Supervisor(self.run, self.root, "/codex")

    def job(self, name, response=None):
        directory = self.run / name
        directory.mkdir()
        test_supervisor.atomic_json(directory / "job.json", {"digest": "current-source"})
        if response is not None:
            test_supervisor.atomic_json(directory / "result.json", response)
        return directory

    def test_failed_test_routes_astra_change_and_test_to_the_next_implementation(self):
        verify = self.job("001-verify")
        run = subprocess.run(
            [sys.executable, "-c", "raise SystemExit('owner changed without approval')"],
            capture_output=True, text=True,
        )
        (verify / "stdout.log").write_text(run.stdout)
        (verify / "stderr.log").write_text(run.stderr)
        self.supervisor.save(phase="verify", pending=verify.name)
        self.supervisor.advance(verify, {"returncode": run.returncode})
        self.assertEqual(self.supervisor.state["phase"], "review")
        self.assertIn("owner changed without approval", self.supervisor.prompt("review"))

        review = self.job("002-review", {
            "decision": "fix",
            "summary": "The failed test demonstrates a takeover on unknown approval.",
            "evidence": "001-verify exited with a failing ownership assertion.",
            "next_change": "Preserve the existing owner when approval is unavailable.",
            "next_test": "A manual request with unknown approval leaves the owner unchanged.",
        })
        self.supervisor.advance(review, {"returncode": 0})
        self.assertEqual(self.supervisor.state["phase"], "plan")
        self.assertIn("Preserve the existing owner", self.supervisor.prompt("plan"))
        self.assertIn("manual request with unknown approval", self.supervisor.prompt("plan"))

        plan = self.job("003-plan", {
            "decision": "implement",
            "objective": "Keep the owner and defer the request.",
            "test": "Check a manual request with unknown approval.",
            "evidence": "Astra requires a concrete failed-approval case.",
        })
        self.supervisor.advance(plan, {"returncode": 0})
        self.assertEqual(self.supervisor.state["phase"], "implement")
        prompt = self.supervisor.prompt("implement")
        self.assertIn("Check a manual request with unknown approval.", prompt)
        self.assertIn("leaves the owner unchanged", prompt)

    def test_old_passing_test_cannot_complete_a_new_source_review(self):
        for name in test_supervisor.EDITABLE:
            path = self.root / name
            path.parent.mkdir(exist_ok=True)
            path.touch()
        self.supervisor.save(
            phase="review", test_code=0, test_job="001-verify", test_digest="older-source",
        )
        review = self.job("002-review", {
            "decision": "complete", "summary": "Ready", "evidence": "Old tests",
            "next_change": "", "next_test": "",
        })
        with self.assertRaisesRegex(RuntimeError, "fixture checks must pass"):
            self.supervisor.advance(review, {"returncode": 0})
        self.assertEqual(self.supervisor.state["phase"], "review")
