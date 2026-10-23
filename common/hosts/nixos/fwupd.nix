# Firmware/UEFI/BIOS updates via fwupd (LVFS) for real x86_64 UEFI hardware
# (T1/T2). Excluded: L2 (legacy BIOS/GRUB, no UEFI capsule path) and ASL1N
# (Apple Silicon — firmware comes from macOS via Asahi's U-Boot flow, not LVFS).
#
# There is no better/more-declarative option here: fwupd/LVFS is the de facto
# cross-vendor standard on Linux, and firmware inherently can't be a Nix-store
# artifact — it gets flashed into hardware, not symlinked into place. This
# module only declares the daemon + policy (enabled, which remotes, ESP
# detection); actually applying an update stays an imperative, operator-run
# step:
#
#   fwupdmgr refresh        # pull latest LVFS metadata (also runs periodically
#                            # via the fwupd-refresh.timer this module enables)
#   fwupdmgr get-updates    # list what's available for this machine
#   fwupdmgr update         # apply
#
# HP's LVFS coverage is real but thin and concentrated on EliteBook/EliteDesk/Z
# workstation lines — there's no known t640 thin-client firmware on LVFS today,
# so `get-updates` returning nothing on T1 is expected, not a misconfiguration.
#
# ESP auto-detection: fwupd's uefi_capsule EspLocation defaults to
# `boot.loader.efi.efiSysMountPoint`, which correctly resolves to `/boot` here
# (both T1 and T2's disko layouts mount the ESP at /boot) — no override needed.
{
  config,
  lib,
  ...
}:
lib.mkIf (lib.elem config.hostSpec.hostName ["T1" "T2"]) {
  services.fwupd.enable = true;
}
