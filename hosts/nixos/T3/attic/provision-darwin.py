"""Ensure the private `darwin` Attic cache exists. Idempotent; never touches `infra`.

Only a ten-minute bootstrap token is minted, held in memory and never logged.
CI and import tokens are minted by the operator (docs/homelab-build-cache.md).
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = "http://127.0.0.1:8080"
CACHE = "darwin"
API = "/_api/v1/cache-config/" + CACHE
STATE = Path("/var/lib/attic-darwin-cache")


def request(path, token=None, method="GET", payload=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        ENDPOINT + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        # Error bodies may echo request details; never surface them.
        return error.code, b""


def wait_for_server():
    # atticd may still be migrating its database right after it starts.
    for _ in range(60):
        try:
            request("/")
            return
        except (urllib.error.URLError, OSError):
            time.sleep(1)
    raise RuntimeError("atticd did not become reachable on 127.0.0.1:8080")


def mint_bootstrap(config):
    command = [
        "atticadm", "-f", config, "make-token",
        "--sub", "darwin-cache-bootstrap", "--validity", "10m",
        "--pull", CACHE, "--create-cache", CACHE, "--configure-cache", CACHE,
    ]
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("Bootstrap token minting failed; command output withheld")
    token = result.stdout.decode().strip()
    if len(token.split(".")) != 3 or any(c.isspace() for c in token):
        raise RuntimeError("Minting did not return a JWT; output withheld")
    return token


def ensure_private(admin):
    status, _ = request(API, admin)
    if status == 404:
        status, _ = request(API, admin, "POST", {
            "keypair": "Generate", "is_public": False, "store_dir": "/nix/store",
            "priority": 41, "upstream_cache_key_names": ["cache.nixos.org-1"],
        })
        if status not in (200, 201, 204):
            raise RuntimeError(f"Private cache creation failed (HTTP {status})")
        print("Created private cache darwin")
    elif status != 200:
        raise RuntimeError(f"Cache inspection failed (HTTP {status})")
    # Re-asserting privacy is safe on every run and never regenerates the keypair.
    status, _ = request(API, admin, "PATCH", {"is_public": False})
    if status not in (200, 204):
        raise RuntimeError(f"Private cache configuration failed (HTTP {status})")
    status, body = request(API, admin)
    config = json.loads(body) if status == 200 else {}
    if config.get("is_public") is not False:
        raise RuntimeError("Cache darwin is still public")
    key = config.get("public_key", "")
    if not key.startswith(CACHE + ":") or any(c.isspace() for c in key):
        raise RuntimeError("Unexpected darwin signing public key")
    authenticated, _ = request(f"/{CACHE}/nix-cache-info", admin)
    anonymous, _ = request(f"/{CACHE}/nix-cache-info")
    if authenticated != 200 or anonymous not in (401, 403, 404):
        raise RuntimeError(f"Anonymous read of darwin not denied (HTTP {anonymous})")
    return key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-config", required=True)
    args = parser.parse_args()
    try:
        wait_for_server()
        key = ensure_private(mint_bootstrap(args.server_config))
        # The verification key is public; CI pins it as DARWIN_CACHE_PUBLIC_KEY.
        STATE.mkdir(mode=0o755, parents=True, exist_ok=True)
        (STATE / "public-key").write_text(key + "\n")
        (STATE / "public-key").chmod(0o644)
    except (RuntimeError, OSError, ValueError, urllib.error.URLError) as error:
        print(f"darwin cache provisioning failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
    print("Private darwin cache ready; anonymous GET denied")
    print("Public key: " + key)


if __name__ == "__main__":
    os.umask(0o022)
    main()
