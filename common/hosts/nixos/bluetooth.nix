# Bluetooth for desktop NixOS hosts (L2/T2/ASL1N). Server/headless hosts (WSL,
# colima, VPS0/VPS1) intentionally have no Bluetooth — no hardware, no point enabling.
#
# Enables the bluez5 daemon and loads kernel modules; replaces the bare `bluez`
# package that used to live in common/hosts/nixos/misc.nix. Add
# `services.bluetooth.audioSupport = true;` here if you pair BT headsets/speakers
# (pulls in PipeWire/PulseAudio modules).
{
  config,
  lib,
  ...
}:
lib.mkIf (lib.elem config.hostSpec.hostName ["L2" "T2" "ASL1N"]) {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
