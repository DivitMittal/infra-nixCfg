"""Join CI to the tailnet using Nix-cached native binaries, without Go builds."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def join():
    cli = shutil.which("tailscale")
    daemon = shutil.which("tailscaled")
    if not cli or not daemon:
        raise RuntimeError("Install the pinned nixpkgs tailscale package first")
    secret = os.environ["TS_OAUTH_SECRET"].strip()
    if not secret.startswith("tskey-client-") or any(c.isspace() for c in secret):
        raise RuntimeError("Expected a Tailscale OAuth client secret")
    directory = Path(os.environ["RUNNER_TEMP"]).resolve()
    socket = str(directory / "darwin-tailscaled.sock")
    run_id = os.environ["GITHUB_RUN_ID"]
    attempt = os.environ["GITHUB_RUN_ATTEMPT"]
    if not run_id.isdecimal() or not attempt.isdecimal():
        raise RuntimeError("Unexpected GitHub run identifiers")
    # The runner keeps the daemon for this job only. It holds ephemeral state.
    with (directory / "darwin-tailscaled.log").open("wb") as log:
        process = subprocess.Popen([
            "sudo", "-n", daemon, "--state=mem:", "--socket=" + socket,
        ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(30):
        if process.poll() is not None:
            raise RuntimeError("tailscaled exited before becoming ready; daemon log retained on runner")
        try:
            status = subprocess.run([
                "sudo", "-n", cli, "--socket=" + socket, "status", "--json",
            ], capture_output=True, timeout=3)
            if status.returncode == 0:
                break
        except subprocess.TimeoutExpired:
            pass
        time.sleep(1)
    else:
        raise RuntimeError("tailscaled did not become ready")
    # Match the official action's ephemeral OAuth flow, keeping the secret out
    # of process arguments and shell tracing.
    with tempfile.NamedTemporaryFile(mode="w", dir=directory) as credential:
        credential.write(secret + "?preauthorized=true&ephemeral=true")
        credential.flush()
        result = subprocess.run([
            "sudo", "-n", cli, "--socket=" + socket, "up",
            "--auth-key=file:" + credential.name, "--advertise-tags=tag:ci",
            f"--hostname=github-darwin-{run_id}-{attempt}",
            "--accept-routes", "--accept-dns=false", "--timeout=120s",
        ], capture_output=True, timeout=135)
        if result.returncode:
            raise RuntimeError("Tailscale enrollment failed; credential-bearing output withheld")
    print("Ephemeral Darwin runner joined the tailnet with subnet routes enabled")


if __name__ == "__main__":
    try:
        join()
    except (RuntimeError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"Darwin tailnet setup failed ({type(error).__name__}): {error}", file=sys.stderr)
        raise SystemExit(1) from None
