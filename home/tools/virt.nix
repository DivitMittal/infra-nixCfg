{
  pkgs,
  lib,
  config,
  hostPlatform,
  ...
}: let
  colimaHome = "${config.xdg.configHome}/colima";
  profileFile = "${colimaHome}/default/colima.yaml";

  # Mirrors the existing `default` VM: colima refuses to change arch, vmType,
  # mountType or network mode after creation and can't shrink the disk, so
  # only cpu/memory are freely adjustable here.
  defaultProfile = (pkgs.formats.yaml {}).generate "colima.yaml" {
    runtime = "docker";
    arch =
      if hostPlatform.isAarch64
      then "aarch64"
      else "x86_64";

    cpu = 6;
    memory = 6;
    disk = 100;

    kubernetes.enabled = false;
    autoActivate = true;

    # vz (Virtualization.framework) only needs macOS 13+, Intel included;
    # qemu isn't installed.
    vmType = "vz";
    mountType = "virtiofs";
    network.mode = "shared";
  };
in {
  # colima manages Lima VMs; macOS-only (launchd-backed)
  # isService = false → no launchd agent; start manually with `colima start`
  services.colima = lib.mkIf hostPlatform.isDarwin {
    enable = true;
    colimaHomeDir = colimaHome;
    coreutilsPackage = pkgs.uutils-coreutils;
    # No `settings` on purpose: the module would link colima.yaml read-only
    # from the store, and a manual `colima start` rewrites that file, failing
    # with "permission denied" (only the module's launchd agent passes
    # --save-config=false). A writable copy is installed below instead.
    profiles.default.isService = false;
  };

  # Reset the profile to the declared state on every switch while keeping it
  # writable. After linkGeneration so HM has already dropped the old symlink.
  home.activation.colimaDefaultProfile = lib.mkIf hostPlatform.isDarwin (
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -p ${lib.escapeShellArg (builtins.dirOf profileFile)}
      run rm -f ${lib.escapeShellArg profileFile}
      run cp ${defaultProfile} ${lib.escapeShellArg profileFile}
      run chmod 644 ${lib.escapeShellArg profileFile}
    ''
  );

  home.packages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      ### container management
      ## docker
      docker
      docker-compose
      lazydocker
      ## kubernetes
      kubectl
      ### virtualization
      #virt-manager libvirt qemu
      ;

    ## kubernetes
    # k9s 0.51.0 tests write to /tmp which the Nix sandbox forbids
    # (permission denied in TestEnsureBenchmarkCfg/TestSkinFileFromName/
    # TestK9sReload); skip the check phase to build.
    k9s = pkgs.k9s.overrideAttrs (_: {doCheck = false;});
  };
}
