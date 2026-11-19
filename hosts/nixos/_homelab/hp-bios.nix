# The current t640 firmware/driver pair exposes malformed attributes. Keep
# discovery separate from enforcement until real setting names are verified.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.hpBiosInventory;
  report = pkgs.writeText "hp-bios-inventory.py" ''
    import json
    import os
    import platform
    import struct
    from pathlib import Path

    errors = []

    def read(path):
        try:
            return Path(path).read_bytes()
        except FileNotFoundError:
            return None
        except OSError as exc:
            # Paths can contain identifiers; report only the error class.
            errors.append(type(exc).__name__)
            return None

    def text(path):
        value = read(path)
        return value.decode("utf-8", errors="replace").strip() if value is not None else None

    attributes = Path("/sys/class/firmware-attributes/hp-bioscfg/attributes")
    try:
        names = os.listdir(attributes)
    except FileNotFoundError:
        names = []
    except OSError as exc:
        names = []
        errors.append(type(exc).__name__)

    # Count only: names and arbitrary setting values may contain private data.
    malformed = sum(not name.isascii() or not name.isprintable() for name in names)
    cpuinfo = text("/proc/cpuinfo")
    svm = None if cpuinfo is None else any(
        "svm" in line.split(":", 1)[1].split()
        for line in cpuinfo.splitlines() if line.startswith("flags") and ":" in line
    )

    efivars = Path("/sys/firmware/efi/efivars")
    guid = "8be4df61-93ca-11d2-aa0d-00e098032b8c"

    def variable(name):
        data = read(efivars / (name + "-" + guid))
        if data is None:
            return None
        if len(data) < 4:
            errors.append("TruncatedEfiVariable")
            return None
        return data[4:]  # efivarfs prefixes the UEFI payload with attributes.

    order = variable("BootOrder")
    entries = []
    if order is not None:
        if len(order) % 2:
            errors.append("MalformedBootOrder")
        else:
            for (number,) in struct.iter_unpack("<H", order):
                data = variable(f"Boot{number:04X}")
                kind = "unknown"
                active = None
                if data is not None:
                    if len(data) < 8:
                        errors.append("TruncatedBootEntry")
                    else:
                        active = bool(struct.unpack_from("<I", data)[0] & 1)
                        end = next((i for i in range(6, len(data) - 1, 2)
                                    if data[i:i + 2] == b"\x00\x00"), None)
                        if end is None:
                            errors.append("UnterminatedBootDescription")
                        else:
                            label = data[6:end].decode("utf-16-le", errors="replace").lower()
                            kind = ("linux-boot-manager" if label == "linux boot manager" else
                                    "network" if any(s in label for s in ("pxe", "ipv4", "ipv6", "network")) else
                                    "other")
                # Never emit descriptions or device paths (these can contain MACs).
                entries.append({"id": f"{number:04X}", "kind": kind, "active": active})

    linux = [i for i, e in enumerate(entries) if e["kind"] == "linux-boot-manager" and e["active"]]
    network = [i for i, e in enumerate(entries) if e["kind"] == "network" and e["active"]]
    precedence = None
    if linux and network and all(e["kind"] != "unknown" for e in entries):
        precedence = min(linux) < min(network)

    print(json.dumps({
        "schema": 1,
        "kernel": platform.release(),
        "bios_version": text("/sys/class/dmi/id/bios_version"),
        "bios_date": text("/sys/class/dmi/id/bios_date"),
        "hp_attributes_present": attributes.is_dir(),
        "hp_attribute_entries": len(names),
        "hp_malformed_names": malformed,
        "driver_pending_reboot": text(attributes / "pending_reboot"),
        "svm_cpu_flag": svm,
        "kvm_amd_loaded": Path("/sys/module/kvm_amd").is_dir(),
        "kvm_device_present": Path("/dev/kvm").exists(),
        "uefi_boot_order": entries,
        "linux_before_network_by_label": precedence,
        "errors": errors,
    }, indent=2))
    raise SystemExit(1 if errors else 0)
  '';
  inventory = pkgs.writeShellScriptBin "hp-bios-inventory" ''
    exec ${pkgs.python3}/bin/python3 ${report}
  '';
in {
  options.hardware.hpBiosInventory = {
    enable = lib.mkEnableOption "read-only HP BIOS and UEFI inventory";
    candidateDriver = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.callPackage ../../../pkgs/custom/hp-bioscfg-m43/package.nix {
        inherit (config.boot.kernelPackages) kernel;
      };
      description = ''
        Experimental M43 driver built for this host's configured kernel.
        This exposes a build target only; it neither installs nor loads the module.
        Building and live testing require coordination described in docs/hp-t640-bios.md.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = ["hp-bioscfg"];
    environment.systemPackages = [inventory];
  };
}
