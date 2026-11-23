"""Find and remove stale rows from the macOS TCC (privacy permissions) databases.

Every nix rebuild moves binaries to a new /nix/store path, and macOS keys
path-based grants on the exact path, so old grants pile up forever. Apps that
were uninstalled years ago also keep their rows. This tool reports (default)
or deletes (--apply) such rows. A timestamped backup is written before any
delete, and Apple-owned clients (com.apple.*) are never touched.

Categories:
  path-gone       path client (client_type 1) that no longer exists on disk
  nix-stale       /nix/store path that exists but is outside the current
                  system/home-manager closures (superseded, awaiting GC)
  app-missing     bundle-ID client with no installed bundle
  target-missing  AppleEvents grant whose target app is not installed
  superseded      --superseded-by: other store paths of the same program
"""

import argparse
import datetime
import os
import plistlib
import pwd
import sqlite3
import subprocess
import sys

TCC_REL = "Library/Application Support/com.apple.TCC/TCC.db"
SYSTEM_DB = "/" + TCC_REL
CATEGORIES = ("path-gone", "nix-stale", "app-missing", "target-missing")
# Limit the bundle walk; nested helpers/plug-ins rarely sit deeper than this.
MAX_DEPTH = 7
KEEP_BACKUPS = 5


def target_user():
    """The human user, even when run via sudo, osascript or root activation.

    Root launched without sudo (osascript "with administrator privileges")
    has no SUDO_USER; fall back to whoever owns the console. Guessing wrong
    here hides ~/Applications and the home-manager closure, so callers must
    not run user-dependent categories without a user.
    """
    name = os.environ.get("TCC_PRUNE_USER") or os.environ.get("SUDO_USER")
    if not name and os.geteuid() != 0:
        name = pwd.getpwuid(os.getuid()).pw_name
    if not name:
        try:
            uid = os.stat("/dev/console").st_uid
            name = pwd.getpwuid(uid).pw_name if uid != 0 else None
        except (OSError, KeyError):
            name = None
    if not name:
        return None
    return pwd.getpwnam(name)


def bundle_roots(home):
    roots = [
        "/Applications",
        "/System/Applications",
        "/Library/Application Support",
        "/Library/Audio/Plug-Ins",
        "/Library/PreferencePanes",
        "/Library/PrivilegedHelperTools",
        "/Library/Input Methods",
        "/Library/SystemExtensions",
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom",
    ]
    if home:
        roots += [
            os.path.join(home, "Applications"),
            os.path.join(home, "Library/Application Support"),
            os.path.join(home, "Library/Audio/Plug-Ins"),
        ]
    return [r for r in roots if os.path.isdir(r)]


def read_bundle_id(plist_path):
    try:
        with open(plist_path, "rb") as fh:
            return plistlib.load(fh).get("CFBundleIdentifier")
    except Exception:  # unreadable/foreign plists are expected; skip them
        return None


def installed_bundle_ids(home):
    """Collect CFBundleIdentifier of every bundle under the usual roots."""
    ids, seen = set(), set()
    for root in bundle_roots(home):
        stack = [(root, 0)]
        while stack:
            path, depth = stack.pop()
            real = os.path.realpath(path)
            if real in seen:
                continue
            seen.add(real)
            bid = read_bundle_id(os.path.join(path, "Contents", "Info.plist"))
            if bid:
                ids.add(bid)
            if depth >= MAX_DEPTH:
                continue
            try:
                entries = os.scandir(path)
            except OSError:
                continue
            with entries:
                for e in entries:
                    try:
                        if e.is_dir():  # follows symlinks (Nix/HM app links)
                            stack.append((e.path, depth + 1))
                    except OSError:
                        continue
    return ids


def spotlight_has(bundle_id):
    """Second opinion for bundles outside the walked roots."""
    try:
        out = subprocess.run(
            ["mdfind", f"kMDItemCFBundleIdentifier == '{bundle_id}'"],
            capture_output=True, text=True, timeout=10, check=False,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    return bool(out.strip())


def live_store_paths(user):
    """Store paths in the current system and home-manager closures."""
    roots = ["/run/current-system"]
    if user:
        roots += [
            f"/etc/profiles/per-user/{user.pw_name}",
            os.path.join(user.pw_dir, ".local/state/nix/profiles/home-manager"),
            f"/nix/var/nix/profiles/per-user/{user.pw_name}/home-manager",
        ]
    live = set()
    for r in roots:
        if not os.path.exists(r):
            continue
        res = subprocess.run(
            ["nix-store", "-qR", r], capture_output=True, text=True, check=False,
        )
        if res.returncode != 0:
            sys.exit(f"tcc-prune: nix-store -qR {r} failed: {res.stderr.strip()}")
        live.update(res.stdout.split())
    return live


def store_root(path):
    parts = path.split("/")
    return "/".join(parts[:4]) if len(parts) > 3 else path


def classify(row, ctx, wanted):
    """First wanted category the row falls in; expensive probes stay lazy."""
    _, client, ctype, target = row
    if ctype == 1:
        if not os.path.exists(client):
            return "path-gone"
        if ("nix-stale" in wanted and client.startswith("/nix/store/")
                and store_root(client) not in ctx["live"]()):
            return "nix-stale"
        return None
    if client.startswith("com.apple."):
        return None
    if "app-missing" in wanted and not ctx["has"](client):
        return "app-missing"
    if ("target-missing" in wanted and target != "UNUSED"
            and not target.startswith("com.apple.") and not ctx["has"](target)):
        return "target-missing"
    return None


def superseded(row, keep):
    """Same program (identical path below the store dir), different store path."""
    _, client, ctype, _ = row
    if ctype != 1 or not client.startswith("/nix/store/") or client == keep:
        return False
    return client.split("/", 4)[4:] == keep.split("/", 4)[4:]


def backup(db):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = f"{db}.bak-{stamp}"
    src, dst = sqlite3.connect(f"file:{db}?mode=ro", uri=True), sqlite3.connect(dest)
    try:
        src.backup(dst)
    finally:
        src.close()
        dst.close()
    # Activation prunes on most rebuilds; keep the folder from filling up.
    folder, prefix = os.path.split(db)
    olds = sorted(f for f in os.listdir(folder or ".") if f.startswith(prefix + ".bak-"))
    for f in olds[:-KEEP_BACKUPS]:
        os.remove(os.path.join(folder, f))
    return dest


def process_db(db, args, ctx):
    try:
        con = sqlite3.connect(f"file:{db}?mode={'rw' if args.apply else 'ro'}", uri=True)
        rows = con.execute(
            "SELECT service, client, client_type, indirect_object_identifier FROM access"
        ).fetchall()
    except sqlite3.Error as err:
        hint = "run with sudo" if db == SYSTEM_DB else "grant your terminal Full Disk Access"
        print(f"tcc-prune: cannot open {db}: {err} ({hint})", file=sys.stderr)
        return False

    doomed = []
    for row in rows:
        if args.nix_only and not row[1].startswith("/nix/store/"):
            continue
        if args.superseded_by:
            why = "superseded" if superseded(row, args.superseded_by) else None
        else:
            why = classify(row, ctx, args.only)
        if why and why in args.only:
            doomed.append((why, row))

    if not args.quiet or doomed:
        print(f"== {db}: {len(doomed)}/{len(rows)} stale")
    for why, (service, client, _, target) in sorted(doomed):
        tgt = "" if target == "UNUSED" else f" -> {target}"
        print(f"  {why:15} {service.removeprefix('kTCCService'):22} {client}{tgt}")

    if args.apply and doomed:
        print(f"  backup: {backup(db)}")
        with con:
            con.executemany(
                "DELETE FROM access WHERE service=? AND client=? AND client_type=?"
                " AND indirect_object_identifier=?",
                [row for _, row in doomed],
            )
        print(f"  deleted {len(doomed)} rows")
    con.close()
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--apply", action="store_true", help="back up, then delete (default: report only)")
    p.add_argument("--db", choices=("user", "system", "both"), default="both")
    p.add_argument("--only", default=",".join(CATEGORIES),
                   help="comma-separated categories to act on (default: all)")
    p.add_argument("--nix-only", action="store_true", help="only consider /nix/store path clients")
    p.add_argument("--superseded-by", metavar="PATH",
                   help="only remove other store paths of this program (implies --only superseded)")
    p.add_argument("--quiet", action="store_true", help="print nothing for clean databases")
    p.add_argument("--db-path", action="append", metavar="PATH",
                   help="operate on this TCC.db copy instead of --db (repeatable)")
    args = p.parse_args()

    args.only = {"superseded"} if args.superseded_by else set(args.only.split(","))
    unknown = args.only - set(CATEGORIES) - {"superseded"}
    if unknown:
        p.error(f"unknown categories: {', '.join(sorted(unknown))}")

    user = target_user()
    needs_user = args.only & {"app-missing", "target-missing", "nix-stale"}
    if needs_user and not user:
        p.error(f"cannot determine the user, needed for {', '.join(sorted(needs_user))};"
                " set TCC_PRUNE_USER")
    dbs = list(args.db_path or [])
    if not dbs and args.db in ("user", "both"):
        if not user:
            p.error("cannot determine the user; set TCC_PRUNE_USER")
        dbs.append(os.path.join(user.pw_dir, TCC_REL))
    if not args.db_path and args.db in ("system", "both"):
        dbs.append(SYSTEM_DB)

    # Lazy: bundle walks and closure queries only run if a row needs them.
    cache = {}

    def has(bid):
        if "ids" not in cache:
            cache["ids"] = installed_bundle_ids(user.pw_dir if user else None)
            cache["absent"] = set()
        if bid in cache["ids"]:
            return True
        if bid in cache["absent"]:
            return False
        if spotlight_has(bid):
            cache["ids"].add(bid)
            return True
        cache["absent"].add(bid)
        return False

    def live():
        if "live" not in cache:
            cache["live"] = live_store_paths(user)
        return cache["live"]

    ok = all([process_db(db, args, {"has": has, "live": live}) for db in dbs])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
