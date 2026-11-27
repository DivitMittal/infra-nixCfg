{
  config,
  pkgs,
  ...
}: let
  home = config.user.home;
  sshdDirectory = "${home}/.sshd";
  hostKey = "${sshdDirectory}/ssh_host_rsa_key";
  port = 8022;

  # The home-lab key (same as hosts/nixos/_homelab/base.nix), so a phone or
  # tablet is reached with the key every other box already trusts.
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI";

  # Lives in the store so a deploy changes it; only the host key is per-device.
  sshdConfig = pkgs.writeText "sshd_config" ''
    HostKey ${hostKey}
    Port ${toString port}
    PidFile ${sshdDirectory}/sshd.pid
    AuthorizedKeysFile ${home}/.ssh/authorized_keys
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    # sshd hands sessions a bare /usr/bin:/bin, so non-interactive commands
    # (deploy-rs, `ssh M1 cmd`) and fish's own config can't find anything.
    SetEnv PATH=${home}/.nix-profile/bin:/usr/bin:/bin
  '';

  sshd-start = pkgs.writeScriptBin "sshd-start" ''
    #!${pkgs.runtimeShell}
    echo "Starting sshd on port ${toString port}"
    exec ${pkgs.openssh}/bin/sshd -f ${sshdConfig} -D
  '';

  # Detaches instead of holding the boot runner; sshd needs an absolute path
  # because it re-executes itself.
  bootScript = pkgs.writeScript "sshd-boot" ''
    #!${pkgs.runtimeShell}
    exec ${pkgs.openssh}/bin/sshd -f ${sshdConfig}
  '';
in {
  environment.packages = [sshd-start];

  build.activation.sshd-setup = ''
    $DRY_RUN_CMD mkdir $VERBOSE_ARG -p "${sshdDirectory}" "${home}/.ssh" "${home}/.termux/boot"

    # Checked per file, not per directory: a hand-started sshd may already
    # have created ~/.sshd without this host key.
    if [[ ! -f "${hostKey}" ]]; then
      $VERBOSE_ECHO "Generating host key..."
      $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -q -t rsa -b 4096 -f "${hostKey}" -N ""
    fi

    # Overwritten on every activation, so this list is the whole truth. The
    # device's own host key stays in it because the deploy nodes (and older
    # workstations) log in with a copy of that key.
    $DRY_RUN_CMD sh -c '{ echo "${sshPubKey} homelab"; cat "${hostKey}.pub"; } > "${home}/.ssh/authorized_keys"'
    $DRY_RUN_CMD chmod 600 "${home}/.ssh/authorized_keys"

    # Termux Launcher's boot add-on runs these once Android has booted.
    $DRY_RUN_CMD ln -sf ${bootScript} "${home}/.termux/boot/sshd"
  '';
}
