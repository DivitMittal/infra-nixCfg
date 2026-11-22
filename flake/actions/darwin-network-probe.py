"""Measure a bounded benign transfer without exposing tailnet or auth details."""

import json
import os
from pathlib import Path
import subprocess
import time


def connection(cli):
    result = subprocess.run(cli + ["status", "--json"], capture_output=True, check=True)
    status = json.loads(result.stdout)
    routers = [
        peer for peer in status.get("Peer", {}).values()
        if "192.168.2.0/24" in peer.get("PrimaryRoutes", [])
    ]
    for peer in routers:
        print(json.dumps({
            "router_online": peer.get("Online"), "direct": bool(peer.get("CurAddr")),
            "relay": peer.get("Relay"), "tx_bytes": peer.get("TxBytes"),
            "rx_bytes": peer.get("RxBytes"),
        }), flush=True)
    return routers


def main():
    directory = Path(os.environ["RUNNER_TEMP"]).resolve()
    cli = ["sudo", "-n", "tailscale", "--socket=" + str(directory / "darwin-tailscaled.sock")]
    routers = connection(cli)
    if routers:
        peer = routers[0]["TailscaleIPs"][0]
        ping = subprocess.run(cli + ["ping", "--c=3", "--timeout=5s", peer], capture_output=True, timeout=20)
        print("router_ping_success=" + str(ping.returncode == 0), flush=True)
    netcheck = subprocess.run(cli + ["netcheck"], capture_output=True, timeout=30)
    for line in (netcheck.stdout + netcheck.stderr).decode(errors="replace").splitlines():
        if any(label in line for label in ["UDP:", "MappingVariesByDestIP:", "PortMapping:", "Nearest DERP:"]):
            print(line.strip(), flush=True)
    fixture = directory / ("cache-network-probe-" + os.environ["GITHUB_RUN_ID"])
    fixture.write_bytes(os.urandom(8 * 1024 * 1024))
    store_path = subprocess.check_output(["nix-store", "--add", str(fixture)], text=True).strip()
    target = os.environ["ATTIC_REMOTE"] + ":" + os.environ["ATTIC_DARWIN_CACHE"]
    started = time.monotonic()
    try:
        upload = subprocess.run(["attic", "push", "--no-closure", "-j", "1", target, store_path], capture_output=True, timeout=90)
    except subprocess.TimeoutExpired:
        print("upload_timeout_seconds=90 fixture_bytes=" + str(fixture.stat().st_size), flush=True)
        connection(cli)
        return
    elapsed = time.monotonic() - started
    print(json.dumps({"upload_exit": upload.returncode, "upload_seconds": elapsed, "fixture_bytes": fixture.stat().st_size}), flush=True)
    connection(cli)
    if upload.returncode:
        raise SystemExit("Fixture upload failed; response withheld")
    started = time.monotonic()
    try:
        subprocess.run([
            "nix", "copy", "--from", os.environ["ATTIC_ENDPOINT"] + "/" + os.environ["ATTIC_DARWIN_CACHE"],
            "--to", "local?root=" + str(directory / "network-probe-store"),
            "--option", "require-sigs", "true", "--option", "trusted-public-keys", os.environ["DARWIN_CACHE_PUBLIC_KEY"],
            store_path,
        ], capture_output=True, check=True, timeout=90)
    except subprocess.TimeoutExpired:
        print("download_timeout_seconds=90", flush=True)
        return
    print("download_seconds=" + str(time.monotonic() - started), flush=True)


if __name__ == "__main__":
    main()
