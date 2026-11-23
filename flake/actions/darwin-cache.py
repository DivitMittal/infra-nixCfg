"""Validate a private cache before allowing a Darwin closure upload."""

import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

# Set by flake/actions/darwin-offload.nix from the shared attic settings.
ENDPOINT = os.environ["ATTIC_ENDPOINT"].rstrip("/")
CACHE = os.environ["ATTIC_DARWIN_CACHE"]
REMOTE = os.environ["ATTIC_REMOTE"]


def get(path, token=None):
    headers = {} if token is None else {"Authorization": "Bearer " + token}
    request = urllib.request.Request(ENDPOINT + path, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, b""


def check():
    token = os.environ["ATTIC_DARWIN_TOKEN"].strip()
    expected_key = os.environ["DARWIN_CACHE_PUBLIC_KEY"].strip()
    status, body = get("/_api/v1/cache-config/" + CACHE, token)
    config = json.loads(body) if status == 200 else {}
    if config.get("is_public") is not False:
        raise RuntimeError(f"Cache {CACHE} must exist and be private (HTTP {status})")
    if not expected_key.startswith(CACHE + ":") or config.get("public_key") != expected_key:
        raise RuntimeError("Darwin signing key does not match its pinned public key")
    if config.get("substituter_endpoint", "").rstrip("/") != ENDPOINT + "/" + CACHE:
        raise RuntimeError("Unexpected substitute endpoint")
    if config.get("api_endpoint", "").rstrip("/") != ENDPOINT:
        raise RuntimeError("Unexpected delegated API endpoint")
    authenticated, _ = get(f"/{CACHE}/nix-cache-info", token)
    anonymous, _ = get(f"/{CACHE}/nix-cache-info")
    if authenticated != 200 or anonymous not in (401, 403, 404):
        raise RuntimeError("Anonymous cache GET must be denied")
    config_dir = Path.home() / ".config/attic"
    config_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    config_dir.chmod(0o700)
    config_file = config_dir / "config.toml"
    # Fresh hosted runner: no other token-bearing Attic config is used here.
    fd = os.open(config_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as out:
        out.write(f'[servers.{REMOTE}]\nendpoint = "{ENDPOINT}/"\ntoken = ' + json.dumps(token) + "\n")
    config_file.chmod(0o600)
    if len(sys.argv) > 1:
        # Probe the actual newly uploaded narinfo, not only cache metadata.
        name = Path(os.path.realpath(sys.argv[1])).name
        store_hash = name.split("-", 1)[0]
        if len(store_hash) != 32 or not store_hash.isalnum():
            raise RuntimeError("Invalid probe store hash")
        status, _ = get(f"/{CACHE}/{store_hash}.narinfo")
        if status not in (401, 403, 404):
            raise RuntimeError("Anonymous narinfo GET was not denied")
    print("private_cache=true pinned_signing_key=true anonymous_get_denied=true")


if __name__ == "__main__":
    try:
        check()
    except (RuntimeError, OSError, KeyError, ValueError, urllib.error.URLError) as error:
        print(f"Darwin cache validation failed ({type(error).__name__}); response bodies withheld", file=sys.stderr)
        raise SystemExit(1) from None
