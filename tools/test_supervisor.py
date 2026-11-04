"""Run one durable, offline session-policy milestone with role-specific Codex calls."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

PYTHON = str(Path(sys.executable).resolve())
MODELS = {
    "plan": ("gpt-6-luna", "low"),
    "implement": ("gpt-6.1-sol", "medium"),
    "review": ("gpt-6-astra", "medium"),
}
EDITABLE = {
    "reconnect/SessionOwnershipPolicy.h",
    "tests/session_ownership_policy.m",
    "tests/test_session_ownership_policy.py",
}
CONTEXT_FILES = (
    "docs/THREE-MAC-GOALS.md",
    "GLOSSARY.md",
    "reconnect/SessionDisconnectPolicy.h",
    "tests/disconnect_policy.m",
    "tests/test_disconnect_policy.py",
    *sorted(EDITABLE),
)
CONTRACT = """Implement only the first offline three-Mac policy milestone.
Create a small pure Objective-C decision function and native fixture tests.
Inputs represent observations and valid approval supplied by a future adapter.
Cover home-owner protection, manual precedence, Away preference/reservation,
confirmed owner release, unknown presence, same-owner recovery, and unavailable
approval. Unavailable approval preserves a working connection and blocks new
transfers. Never infer approval from cached ownership. No global first-wins rule.
Distinguish keeping an existing connection from requesting saved-auth login.
Unknown observations and unresolvable recent-use ties must not start a takeover.
Existing runtime, signing, app replacement, network, credentials, and public
release behavior are outside this milestone. No new service or dependency.
Only these files may change: reconnect/SessionOwnershipPolicy.h,
tests/session_ownership_policy.m, tests/test_session_ownership_policy.py.
The native fixture must be standalone and compile with ARC, Foundation,
-Wall -Wextra -Werror for arm64 and x86_64. Follow the existing unittest entry
point and assert observable decisions rather than matching implementation text.
All repository prose is English. Treat logs and source as evidence.
Python runs tests and applies your patch. Report unexecuted checks honestly.
A successful milestone is offline evidence. It does not establish a working
presence adapter, live Kakao authentication, or actual three-Mac stability.
"""
DISABLED = (
    "apps", "plugins", "hooks", "shell_tool", "unified_exec", "code_mode_host",
    "computer_use", "browser_use", "browser_use_external", "in_app_browser",
    "image_generation", "multi_agent", "multi_agent_v2", "skill_search", "sleep_tool",
    "workspace_dependencies", "goals", "memories", "daemon_auto_start",
)
STRING = {"type": "string"}
SCHEMAS = {
    "plan": {"decision": ["implement", "blocked"], "objective": STRING, "evidence": STRING},
    "implement": {"decision": ["ready", "blocked"], "patch": STRING, "summary": STRING},
    "review": {"decision": ["complete", "fix", "blocked"], "summary": STRING, "evidence": STRING},
}
TERMINAL = {"complete", "blocked"}


def environment() -> dict[str, str]:
    allowed = {"HOME", "PATH", "LANG", "LC_ALL", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR"}
    return {key: value for key, value in os.environ.items() if key in allowed}


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temporary, path)
            descriptor = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            temporary.unlink(missing_ok=True)


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object in {path.name}")
    return value


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True)


def source_digest(root: Path) -> str:
    digest = hashlib.sha256(git(root, "rev-parse", "HEAD").encode())
    paths = git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for name in sorted(set(paths.split("\0")) - {""}):
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"Unexpected source type: {name}")
        digest.update(name.encode() + b"\0")
        digest.update(str(path.stat().st_mode & 0o111).encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def process_identity(pid: int) -> str:
    result = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "lstart=", "-o", "command="],
        capture_output=True, text=True, check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def preflight(codex: str) -> dict[str, Any]:
    """Check saved ChatGPT authentication, plan usage, and exact model efforts."""
    with tempfile.TemporaryDirectory(prefix="kakao-model-check-") as scratch:
        process = subprocess.Popen(
            [codex, "app-server", "--listen", "stdio://", "-c", "mcp_servers={}",
             "-c", 'model_provider="openai"'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            cwd=scratch, env=environment(),
        )
        assert process.stdin is not None and process.stdout is not None
        target, source = process.stdin, process.stdout
        buffer = b""

        def send(message: dict[str, Any]) -> None:
            target.write((json.dumps(message) + "\n").encode())
            target.flush()

        def request(identifier: int, method: str, params: dict[str, Any]) -> dict[str, Any]:
            nonlocal buffer
            send({"id": identifier, "method": method, "params": params})
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if b"\n" not in buffer:
                    wait = max(0, deadline - time.monotonic())
                    if not select.select([source], [], [], wait)[0]:
                        break
                    chunk = os.read(source.fileno(), 65536)
                    if not chunk:
                        break
                    buffer += chunk
                    continue
                line, buffer = buffer.split(b"\n", 1)
                response = json.loads(line)
                if response.get("id") == identifier:
                    if "error" in response:
                        raise RuntimeError(f"Codex metadata rejected {method}")
                    return response["result"]
            raise RuntimeError(f"Codex metadata did not respond to {method}")

        try:
            request(0, "initialize", {
                "clientInfo": {"name": "kakao_test_supervisor", "version": "1.0"},
            })
            send({"method": "initialized", "params": {}})
            account = request(1, "account/read", {"refreshToken": False}).get("account") or {}
            if account.get("type") != "chatgpt":
                raise RuntimeError("Saved ChatGPT authentication is required")
            quota = request(2, "account/rateLimits/read", {})
            limits = quota.get("rateLimitsByLimitId") or {"codex": quota.get("rateLimits") or {}}
            windows = [
                window["usedPercent"]
                for bucket in limits.values() if isinstance(bucket, dict)
                for name in ("primary", "secondary")
                if isinstance(window := bucket.get(name), dict)
                and isinstance(window.get("usedPercent"), (int, float))
            ]
            if quota.get("ordinaryUsageAllowed") is not True or not windows or max(windows) >= 100:
                raise RuntimeError("Included ChatGPT plan usage could not be confirmed")
            models = request(3, "model/list", {"limit": 100, "includeHidden": False})["data"]
            catalog = {
                item["model"]: {row["reasoningEffort"] for row in item["supportedReasoningEfforts"]}
                for item in models
            }
            for name, effort in MODELS.values():
                if effort not in catalog.get(name, set()):
                    raise RuntimeError(f"Requested model/effort unavailable: {name}/{effort}")
            return {"auth": "chatgpt", "used_percent": windows, "models": MODELS}
        finally:
            target.close()
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            source.close()


def worker(directory: Path) -> int:
    """Own the child result even if the parent supervisor restarts."""
    with (directory / "worker.claim").open("x") as claim:
        claim.write(f"{os.getpid()}\n")
    identity = process_identity(os.getpid())
    if not identity:
        raise RuntimeError("Worker identity is unavailable")
    atomic_json(directory / "worker.json", {"pid": os.getpid(), "identity": identity})
    spec = read_json(directory / "job.json")
    env = environment()
    env["TMPDIR"] = str(directory / "scratch")
    (directory / "scratch").mkdir()
    try:
        with (
            (directory / "input.txt").open("rb") as source,
            (directory / "stdout.log").open("wb") as output,
            (directory / "stderr.log").open("wb") as errors,
        ):
            child = subprocess.Popen(
                spec["argv"], cwd=spec["worktree"], env=env,
                stdin=source, stdout=output, stderr=errors,
            )
            atomic_json(directory / "child.json", {
                "pid": child.pid, "identity": process_identity(child.pid),
            })
            code = child.wait()
    except OSError as error:
        atomic_json(directory / "exit.json", {
            "returncode": -1, "finished_at": time.time(), "error": type(error).__name__,
        })
        return 1
    atomic_json(directory / "exit.json", {"returncode": code, "finished_at": time.time()})
    return 0


def model_result(path: Path, role: str) -> dict[str, str]:
    result = read_json(path)
    schema = SCHEMAS[role]
    if result.keys() != schema.keys() or any(
        not isinstance(value, str) for value in result.values()
    ):
        raise RuntimeError(f"Invalid {role} result fields")
    if result["decision"] not in schema["decision"]:
        raise RuntimeError(f"Invalid {role} decision")
    return result


def test_command(root: Path, directory: Path, stage: str) -> list[str]:
    scratch = directory / "scratch"
    profile = ["(version 1)", "(allow default)", "(deny network*)", "(deny file-write*)"]
    for path in (scratch, root):
        profile.append(f"(allow file-write* (subpath {json.dumps(str(path))}))")
    profile.append('(allow file-write* (literal "/dev/null"))')
    profile.append(f"(deny file-read* (subpath {json.dumps(str(Path.home()))}))")
    for path in (root, scratch, Path(PYTHON).parent.parent):
        profile.append(f"(allow file-read* (subpath {json.dumps(str(path))}))")
    controller = Path(__file__).resolve()
    profile.append(f"(allow file-read* (literal {json.dumps(str(controller))}))")
    sandbox = directory / "offline.sb"
    sandbox.write_text("\n".join(profile) + "\n")
    if stage == "baseline":
        command = [PYTHON, "-m", "unittest", "discover", "-s", "tests", "-v"]
    else:
        command = [
            PYTHON, str(Path(__file__).resolve()), "verify",
            "--worktree", str(root), "--run", str(scratch),
        ]
    return ["/usr/bin/sandbox-exec", "-f", str(sandbox), *command]


def verify(root: Path, directory: Path) -> int:
    test = subprocess.run(
        [PYTHON, "-m", "unittest", "discover", "-s", "tests", "-v"], cwd=root,
    )
    if test.returncode:
        return test.returncode
    binary = directory / "session-policy-fixture"
    build = subprocess.run([
        "/usr/bin/xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
        "-arch", "arm64", "-arch", "x86_64", "-mmacosx-version-min=13.0",
        "-framework", "Foundation", "-I", str(root / "reconnect"),
        str(root / "tests/session_ownership_policy.m"), "-o", str(binary),
    ], cwd=root)
    if build.returncode:
        return build.returncode
    arches = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()
    if set(arches) != {"arm64", "x86_64"}:
        raise RuntimeError("Policy fixture is not universal")
    return subprocess.run([str(binary)], cwd=root).returncode


class Supervisor:
    def __init__(self, run: Path, root: Path, codex: str) -> None:
        self.run, self.root, self.codex = run, root, codex
        self.path = run / "status.json"
        identity = {
            "worktree": str(root), "base": git(root, "rev-parse", "HEAD").strip(),
            "controller_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "codex": codex,
        }
        self.state = read_json(self.path) if self.path.exists() else {
            **identity, "phase": "baseline", "history": [], "attempts": [], "pending": None,
        }
        if any(self.state.get(key) != value for key, value in identity.items()):
            raise RuntimeError("Run source, controller, or Codex identity changed")
        if not self.path.exists() and git(root, "status", "--porcelain"):
            raise RuntimeError("A new run needs a clean dedicated worktree")
        self.save()

    def save(self, **fields: Any) -> None:
        self.state.update(fields)
        atomic_json(self.path, self.state)

    def prompt(self, role: str) -> str:
        context = [
            f"File {name}\n{(self.root / name).read_text()}"
            for name in CONTEXT_FILES if (self.root / name).is_file()
        ]
        last = self.state.get("test_job")
        if last:
            directory = self.run / last
            for name in ("stdout.log", "stderr.log"):
                context.append(f"{name}\n{(directory / name).read_text()[-9000:]}")
        if role == "implement":
            context.append(f"Planner instruction\n{self.state['plan']['objective']}")
        if self.state.get("review"):
            context.append(f"Previous independent review\n{self.state['review']['summary']}")
        if self.state.get("block_proposal"):
            context.append(f"Proposed blocker to verify\n{self.state['block_proposal']}")
        instruction = {
            "plan": "Select the next necessary offline test and fix. A blocker needs evidence.",
            "implement": (
                "Return a git-apply-compatible unified diff in patch. Only the three allowed "
                "paths may change. For a blocker use an empty patch and explain the evidence."
            ),
            "review": (
                "Independently review the actual code and test evidence. Complete only if "
                "the whole offline milestone passes. Use fix for a repairable failure. "
                "Confirm blocked only for an established external prerequisite."
            ),
        }[role]
        return "\n\n".join([CONTRACT, instruction, *context])

    def schedule(self) -> None:
        stage = self.state["phase"]
        digest = source_digest(self.root)
        tracked = git(self.root, "diff", "--name-only", "-z", "HEAD")
        untracked = git(self.root, "ls-files", "--others", "--exclude-standard", "-z")
        if (set((tracked + untracked).split("\0")) - {""}) - EDITABLE:
            raise RuntimeError("Worktree changes exceed the offline milestone allowlist")
        fingerprint = f"{stage}:{digest}"
        if fingerprint in self.state["attempts"]:
            raise RuntimeError("Repeated stage without new source or review evidence")
        name = f"{len(self.state['history']) + 1:03d}-{stage}"
        directory = self.run / name
        directory.mkdir()
        if stage in MODELS:
            atomic_json(directory / "preflight.json", preflight(self.codex))
            model, effort = MODELS[stage]
            fields = SCHEMAS[stage]
            properties = {
                key: {"type": "string", "enum": value} if isinstance(value, list) else value
                for key, value in fields.items()
            }
            schema = directory / "schema.json"
            atomic_json(schema, {
                "type": "object", "additionalProperties": False,
                "required": list(properties), "properties": properties,
            })
            (directory / "input.txt").write_text(self.prompt(stage))
            argv = [
                self.codex, "exec", "--ignore-user-config", "--ephemeral",
                "--sandbox", "read-only", "--cd", str(self.root), "--model", model,
                "--json", "--output-schema", str(schema), "-o", str(directory / "result.json"),
                "-c", 'approval_policy="never"', "-c", 'model_provider="openai"',
                "-c", 'web_search="disabled"', "-c", "mcp_servers={}",
                "-c", f'model_reasoning_effort="{effort}"',
            ]
            for feature in DISABLED:
                argv.extend(["--disable", feature])
            argv.append("-")
        else:
            (directory / "input.txt").touch()
            argv = test_command(self.root, directory, stage)
        atomic_json(directory / "job.json", {
            "argv": argv, "worktree": str(self.root), "digest": source_digest(self.root),
        })
        self.state["attempts"].append(fingerprint)
        self.save(pending=name)
        with (directory / "start.claim").open("x") as claim:
            claim.write(f"{time.time()}\n")
        with (directory / "worker.log").open("ab") as log:
            child = subprocess.Popen(
                [PYTHON, str(Path(__file__).resolve()), "worker", "--run", str(directory)],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=environment(),
                start_new_session=True,
            )
        # Reap finished children while this supervisor is alive.
        self.child = child

    def wait_for_job(self, directory: Path) -> dict[str, Any]:
        while True:
            if (directory / "exit.json").is_file():
                child = getattr(self, "child", None)
                if child is not None:
                    child.poll()
                return read_json(directory / "exit.json")
            identity_path = directory / "worker.json"
            if identity_path.is_file():
                identity = read_json(identity_path)
                if process_identity(identity["pid"]) == identity["identity"]:
                    time.sleep(1)
                    continue
            elif (directory / "start.claim").is_file():
                started = float((directory / "start.claim").read_text())
                if 0 <= time.time() - started < 5:
                    time.sleep(1)
                    continue
            if (directory / "exit.json").is_file():
                continue
            raise RuntimeError("Child identity or exit evidence is missing; job will not rerun")

    def apply(self, directory: Path, patch: str) -> None:
        patch_file = directory / "change.patch"
        patch_file.write_text(patch.rstrip() + "\n")
        stats = git(self.root, "apply", "--recount", "--numstat", "-z", str(patch_file))
        paths = {line.split("\t", 2)[-1] for line in stats.split("\0") if line}
        if not paths or not paths <= EDITABLE:
            raise RuntimeError("Model patch exceeds the offline milestone allowlist")
        summary = git(self.root, "apply", "--recount", "--summary", str(patch_file))
        if any(mode in summary for mode in ("120000", "160000")):
            raise RuntimeError("Model patch includes a symlink or submodule")
        git(self.root, "apply", "--recount", "--check", str(patch_file))
        self.save(phase="applying")
        git(self.root, "apply", "--recount", str(patch_file))
        if source_digest(self.root) == read_json(directory / "job.json")["digest"]:
            raise RuntimeError("Implementation did not change the source")

    def advance(self, directory: Path, result: dict[str, Any]) -> None:
        stage, code = self.state["phase"], result["returncode"]
        digest = read_json(directory / "job.json")["digest"]
        if source_digest(self.root) != digest:
            raise RuntimeError("Source changed while the child was running")
        self.state["history"].append({
            "stage": stage, "job": directory.name, "returncode": code, "digest": digest,
        })
        if stage in {"baseline", "verify"}:
            self.save(
                phase="plan" if stage == "baseline" and code == 0 else "review",
                pending=None, test_job=directory.name, test_code=code, test_digest=digest,
            )
            return
        if code != 0:
            raise RuntimeError(f"{stage} Codex execution failed with exit {code}")
        answer = model_result(directory / "result.json", stage)
        decision = answer["decision"]
        if stage == "plan" and decision == "implement":
            self.save(phase="implement", pending=None, plan=answer)
        elif stage == "implement" and decision == "ready":
            self.apply(directory, answer["patch"])
            self.save(phase="verify", pending=None)
        elif stage == "review":
            if decision == "complete":
                if (
                    self.state["test_code"] != 0
                    or self.state["test_digest"] != digest
                    or not all((self.root / name).is_file() for name in EDITABLE)
                    or not self.state["test_job"].endswith("-verify")
                ):
                    raise RuntimeError("Policy and universal fixture checks must pass")
                self.save(phase="complete", pending=None, review=answer, verified_digest=digest)
            elif decision == "fix":
                tried_implementation = f"implement:{digest}" in self.state["attempts"]
                if self.state.get("block_proposal") and not tried_implementation:
                    plan = {"objective": answer["summary"]}
                    self.save(
                        phase="implement", pending=None, review=answer, plan=plan,
                        block_proposal=None,
                    )
                else:
                    self.save(phase="plan", pending=None, review=answer, block_proposal=None)
            else:
                self.save(phase="blocked", pending=None, review=answer, reason=answer["summary"])
        else:
            self.save(
                phase="review", pending=None,
                block_proposal=answer.get("summary", answer.get("evidence")),
            )

    def execute(self) -> None:
        try:
            while self.state["phase"] not in TERMINAL:
                if self.state["phase"] == "applying":
                    raise RuntimeError("Interrupted patch application needs source reconciliation")
                if not self.state["pending"]:
                    self.schedule()
                directory = self.run / self.state["pending"]
                self.advance(directory, self.wait_for_job(directory))
        except (
            OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError
        ) as error:
            self.save(phase="blocked", reason=f"{type(error).__name__}: {error}")
            raise


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "worker", "verify", "check"))
    parser.add_argument("--run", type=Path)
    parser.add_argument("--worktree", type=Path)
    parser.add_argument("--codex")
    args = parser.parse_args()
    if args.action == "check":
        if not args.codex:
            parser.error("check requires --codex")
        print(json.dumps(preflight(args.codex), indent=2))
        return 0
    if not args.run:
        parser.error("--run is required")
    run = args.run.resolve(strict=True)
    if args.action == "worker":
        return worker(run)
    if not args.worktree:
        parser.error("--worktree is required")
    root = args.worktree.resolve(strict=True)
    if args.action == "verify":
        return verify(root, run)
    if not args.codex:
        parser.error("run requires --codex")
    if root == run or root in run.parents or run in root.parents:
        parser.error("Control directory and worktree must be separate")
    with (run / "supervisor.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        Supervisor(run, root, args.codex).execute()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
