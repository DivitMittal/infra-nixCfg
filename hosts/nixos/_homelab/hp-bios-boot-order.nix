# Keeps the installed boot loader first in UEFI BootOrder. This uses only
# standard UEFI variables, independent of HP's settings interface (see
# docs/hp-t640-bios.md). Entries are matched by ESP PARTUUID and loader path,
# never by Boot#### number, because firmware renumbers entries freely.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.uefiBootOrder;
  script = pkgs.writeText "uefi-boot-order.py" ''
    import argparse
    import fcntl
    import json
    import os
    import struct
    import subprocess
    import sys
    import uuid
    from pathlib import Path

    GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
    LOAD_OPTION_ACTIVE = 0x1
    EXIT_DRIFT = 2


    class Failure(Exception):
        pass


    def parse_args():
        p = argparse.ArgumentParser(
            prog="uefi-boot-order",
            description="Keep the installed boot loader first in UEFI BootOrder.",
        )
        p.add_argument("mode", choices=["check", "plan", "apply"])
        p.add_argument("--loader", required=True,
                       help="loader path on the ESP, e.g. \\EFI\\systemd\\systemd-bootx64.efi")
        p.add_argument("--esp", default="/boot", help="ESP mount point")
        p.add_argument("--esp-partuuid", help="override ESP PARTUUID detection")
        p.add_argument("--efi-dir", default="/sys/firmware/efi",
                       help="absent when the kernel was not booted via UEFI")
        p.add_argument("--efivars", default="/sys/firmware/efi/efivars")
        p.add_argument("--efibootmgr", default="efibootmgr")
        # Shared by the unit and interactive runs so two writers never race.
        p.add_argument("--lock", default="/run/lock/uefi-boot-order.lock")
        return p.parse_args()


    def read_var(efivars, name):
        path = Path(efivars) / f"{name}-{GLOBAL}"
        try:
            data = path.read_bytes()
        except FileNotFoundError:
            return None
        if len(data) < 4:
            raise Failure(f"{name}: truncated efivarfs payload")
        return data[4:]  # efivarfs prefixes the variable attributes


    def boot_order(efivars):
        data = read_var(efivars, "BootOrder")
        if data is None:
            raise Failure("BootOrder is not set; refusing to invent one")
        if len(data) % 2:
            raise Failure("BootOrder has odd length")
        return [n for (n,) in struct.iter_unpack("<H", data)]


    def utf16z(data, start):
        for i in range(start, len(data) - 1, 2):
            if data[i:i + 2] == b"\0\0":
                return data[start:i].decode("utf-16-le", errors="replace"), i + 2
        raise Failure("unterminated UTF-16 string")


    def device_path_nodes(data):
        nodes, i = [], 0
        while i + 4 <= len(data):
            kind, sub, length = struct.unpack_from("<BBH", data, i)
            if length < 4 or i + length > len(data):
                raise Failure("malformed device path node")
            nodes.append((kind, sub, data[i + 4:i + length]))
            if kind == 0x7F and sub == 0xFF:
                break
            i += length
        return nodes


    def parse_load_option(data):
        if len(data) < 6:
            raise Failure("truncated load option")
        attributes, path_len = struct.unpack_from("<IH", data)
        _, end = utf16z(data, 6)
        if end + path_len > len(data):
            raise Failure("load option file path list overruns variable")
        partuuid, files = None, []
        for kind, sub, body in device_path_nodes(data[end:end + path_len]):
            if kind == 0x04 and sub == 0x01 and len(body) >= 38 and body[37] == 0x02:
                partuuid = str(uuid.UUID(bytes_le=bytes(body[20:36])))
            elif kind == 0x04 and sub == 0x04:
                files.append(body.decode("utf-16-le", errors="replace").rstrip("\0"))
        return {
            "active": bool(attributes & LOAD_OPTION_ACTIVE),
            "partuuid": partuuid,
            # Firmware may split a path across several file nodes.
            "file": "\\".join(f.strip("\\") for f in files) if files else None,
        }


    def normalise(path):
        return "\\" + path.replace("/", "\\").strip("\\").lower()


    FALLBACK = "\\efi\\boot\\bootx64.efi"


    def esp_partuuid(esp):
        target = os.path.realpath(esp)
        device = None
        with open("/proc/self/mountinfo") as mounts:
            for line in mounts:
                fields = line.split()
                if fields[4] == target:
                    device = fields[2]  # last match wins for stacked mounts
        if device is None:
            raise Failure(f"{esp} is not a mount point")
        major, minor = (int(x) for x in device.split(":"))
        links = Path("/dev/disk/by-partuuid")
        for link in links.iterdir() if links.is_dir() else []:
            st = os.stat(link)
            if os.major(st.st_rdev) == major and os.minor(st.st_rdev) == minor:
                return link.name.lower()
        raise Failure(f"no PARTUUID found for the device mounted at {esp}")


    def discover(args):
        if not Path(args.efivars).is_dir():
            raise Failure(f"booted via UEFI but {args.efivars} is not mounted")
        order = boot_order(args.efivars)
        partuuid = (args.esp_partuuid or esp_partuuid(args.esp)).lower()
        loader = normalise(args.loader)
        matches = []
        # HP firmware generates its own entry for the disk ("UEFI: SSD ...,
        # Partition 1") and can put it first after a setup change. It boots
        # the same ESP via the removable-media fallback, which systemd-boot
        # also installs, so it is equivalent to the loader entry.
        equivalent = set()
        for name in sorted(os.listdir(args.efivars)):
            stem = name[:-len(GLOBAL) - 1]
            if not (name.endswith(GLOBAL) and len(stem) == 8 and stem.startswith("Boot")):
                continue
            try:
                number = int(stem[4:], 16)
            except ValueError:
                continue
            option = parse_load_option(read_var(args.efivars, stem))
            if option["partuuid"] == partuuid and option["file"] and normalise(option["file"]) == loader:
                matches.append((number, option))
            elif option["partuuid"] == partuuid and option["active"] and (
                option["file"] is None or normalise(option["file"]) == FALLBACK
            ):
                equivalent.add(number)
        if not matches:
            raise Failure("no Boot#### entry points at the configured loader on the ESP")
        if len(matches) > 1:
            ids = ", ".join(f"{n:04X}" for n, _ in matches)
            raise Failure(f"ambiguous: several entries point at the loader ({ids})")
        number, option = matches[0]
        if not option["active"]:
            raise Failure(f"Boot{number:04X} points at the loader but is inactive")
        position = order.index(number) if number in order else len(order)
        if all(n in equivalent for n in order[:position]):
            # Everything ahead of the loader boots it anyway: compliant as is,
            # so never write (that would fight the firmware on every boot).
            return order, list(order), number
        desired = [number] + [n for n in order if n != number]
        return order, desired, number


    def fmt(order):
        return ",".join(f"{n:04X}" for n in order)


    def report(mode, order, desired, target, next_boot, wrote=False):
        print(json.dumps({
            "mode": mode,
            "target": f"{target:04X}",
            "boot_order": fmt(order),
            "desired_boot_order": fmt(desired),
            "compliant": order == desired,
            "boot_next": None if next_boot is None else f"{next_boot:04X}",
            "wrote": wrote,
        }))


    def main():
        args = parse_args()
        if not Path(args.efi_dir).is_dir():
            # Legacy/CSM boot: BootOrder does not govern this machine, so there
            # is nothing to check or enforce. Skipping is not drift.
            print(json.dumps({"mode": args.mode, "skipped": "not booted via UEFI"}))
            print("uefi-boot-order: not booted via UEFI; skipping", file=sys.stderr)
            return 0
        lock = open(args.lock if args.mode == "apply" else os.devnull, "w")
        fcntl.flock(lock, fcntl.LOCK_EX)
        order, desired, target = discover(args)
        raw_next = read_var(args.efivars, "BootNext")
        next_boot = struct.unpack("<H", raw_next[:2])[0] if raw_next and len(raw_next) >= 2 else None
        if next_boot is not None:
            # A pending one-shot boot is someone's deliberate choice; never clear it.
            print(f"warning: BootNext={next_boot:04X} overrides BootOrder once", file=sys.stderr)
        if order == desired or args.mode != "apply":
            report(args.mode, order, desired, target, next_boot)
            return 0 if order == desired or args.mode == "plan" else EXIT_DRIFT
        # Invariant: the only move ever made is the loader to the front. A
        # network entry must never end up above it (a PXE-first node would
        # reinstall or hang on the next boot).
        if desired[0] != target or sorted(desired[1:]) != sorted(n for n in order if n != target):
            raise Failure("internal: refusing a write that is not 'loader first, rest unchanged'")
        subprocess.run([args.efibootmgr, "--quiet", "--bootorder", fmt(desired)],
                       check=True, stdout=subprocess.DEVNULL)
        after = boot_order(args.efivars)
        if after != desired:
            raise Failure(f"BootOrder is {fmt(after)} after writing {fmt(desired)}")
        report(args.mode, after, desired, target, next_boot, wrote=True)
        return 0


    if __name__ == "__main__":
        try:
            sys.exit(main())
        except (Failure, OSError, subprocess.CalledProcessError) as exc:
            print(f"uefi-boot-order: {exc}", file=sys.stderr)
            sys.exit(1)
  '';
  tool = pkgs.writeShellScriptBin "uefi-boot-order" ''
    exec ${pkgs.python3}/bin/python3 -I ${script} \
      --loader ${lib.escapeShellArg cfg.loader} \
      --esp ${lib.escapeShellArg cfg.espMountPoint} \
      --efibootmgr ${pkgs.efibootmgr}/bin/efibootmgr \
      "$@"
  '';
in {
  options.hardware.uefiBootOrder = {
    enable = lib.mkEnableOption "UEFI BootOrder drift detection for the installed boot loader";

    # Check-only by default: a BootOrder write is a firmware NVRAM write that
    # survives rollbacks, has been exercised on real M43 firmware only once
    # (imperatively, on T3), and a wrong order can leave a headless node
    # PXE-looping. Drift detection costs nothing; enforcement is per host.
    mode = lib.mkOption {
      type = lib.types.enum ["check" "enforce"];
      default = "check";
      description = ''
        `check` fails the unit when the loader is not first; `enforce` also
        rewrites BootOrder, but only when it has drifted. Other entries keep
        their relative order, so network boot stays available as a fallback.
        BootNext is reported and never cleared.
      '';
    };

    loader = lib.mkOption {
      type = lib.types.str;
      default = "\\EFI\\systemd\\systemd-bootx64.efi";
      description = "Loader path on the ESP that the first entry must point at.";
    };

    espMountPoint = lib.mkOption {
      type = lib.types.str;
      default = config.boot.loader.efi.efiSysMountPoint;
      defaultText = lib.literalExpression "config.boot.loader.efi.efiSysMountPoint";
      description = "Mount point of the ESP; its PARTUUID must match the entry.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mode == "check" || config.boot.loader.efi.canTouchEfiVariables;
        message = "hardware.uefiBootOrder.mode = \"enforce\" needs boot.loader.efi.canTouchEfiVariables";
      }
    ];

    environment.systemPackages = [tool];

    systemd.services.uefi-boot-order = {
      description = "Keep the installed boot loader first in UEFI BootOrder";
      wantedBy = ["multi-user.target"];
      unitConfig.RequiresMountsFor = [cfg.espMountPoint];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Exit 2 means drift in check mode: the unit fails so it shows up in
        # `systemctl --failed` instead of being silently tolerated.
        ExecStart = "${tool}/bin/uefi-boot-order ${
          if cfg.mode == "enforce"
          then "apply"
          else "check"
        }";
        PrivateNetwork = true;
        NoNewPrivileges = true;
        ProtectHome = true;
        # efivarfs lives under /sys, which ProtectSystem leaves writable;
        # nothing else needs writing except the shared lock.
        ProtectSystem = "strict";
        ReadWritePaths = ["/run/lock"];
        PrivateTmp = true;
      };
    };
  };
}
