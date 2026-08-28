# Perf/FPS overlay for Steam/Proton games. L2-only (see hosts/nixos/L2/gaming.nix
# for the system-level Steam/Proton stack) — the other Linux GUI hosts
# (T2/ASL1N) don't have this gaming setup.
{
  config,
  lib,
  ...
}:
lib.mkIf (config.hostSpec.hostName == "L2") {
  programs.mangohud = {
    enable = true;
    settingsPerApplication = {
      # Rocket League runs through Proton as RocketLeague.exe; keep the
      # overlay minimal so it doesn't eat into frame time on the iGPU.
      RocketLeague = {
        fps_limit = 0;
        frame_timing = true;
        gpu_stats = true;
        cpu_stats = true;
        gpu_temp = true;
        cpu_temp = true;
        position = "top-left";
      };
    };
  };
}
