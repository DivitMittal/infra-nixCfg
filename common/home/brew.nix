{
  config,
  inputs,
  hostPlatform,
  lib,
  pkgs,
  ...
}: let
  ## Standard Homebrew layout: Apple Silicon keeps prefix & repository together
  ## under /opt/homebrew; Intel uses /usr/local with the repo in /usr/local/Homebrew
  prefix =
    if hostPlatform.isAarch64
    then "/opt/homebrew"
    else "/usr/local";
  repository =
    if hostPlatform.isAarch64
    then prefix
    else "${prefix}/Homebrew";
  brewPath = "${prefix}/bin/brew";
  ## nix-homebrew (common/hosts/darwin/brew.nix) owns brew on x86_64-darwin, since
  ## the official installer refuses Intel Macs; elsewhere this module bootstraps it
  brewFromNixDarwin = hostPlatform.isDarwin && hostPlatform.isx86_64;
  ## Marks a nix-homebrew install: expected on Intel, a leftover anywhere else
  nixHomebrewMarker = "${repository}/Library/.homebrew-is-managed-by-nix";

  ## Downloads to a file first: `bash -c "$(curl ...)"` exits 0 on a failed
  ## download, since the failure inside the substitution is swallowed
  installHomebrew = pkgs.writeShellScript "install-homebrew" ''
    set -euo pipefail
    installer="$(${pkgs.coreutils}/bin/mktemp)"
    trap 'rm -f "$installer"' EXIT
    ${pkgs.curl}/bin/curl -fsSL -o "$installer" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
    ${pkgs.bash}/bin/bash "$installer"
  '';

  brew-migrate-from-nix-homebrew = pkgs.writeShellApplication {
    name = "brew-migrate-from-nix-homebrew";
    text = ''
      ## sudo strips SSL_CERT_FILE (curl fails) and Homebrew's installer refuses root
      if [ "$(id -u)" -eq 0 ]; then
        echo "Run without sudo; the script elevates only for the removals." >&2
        exit 1
      fi

      if [ ! -e "${nixHomebrewMarker}" ]; then
        echo "Homebrew at ${prefix} is not managed by nix-homebrew; nothing to do."
        exit 0
      fi

      echo "This replaces nix-homebrew's /nix/store-backed brew shim with a standard Homebrew install."
      echo "Cellar, Caskroom and third-party taps are kept. Removes (with sudo):"
      echo "  ${brewPath}  ${repository}/Library/Homebrew  ${nixHomebrewMarker}"
      echo "  ${repository}/Library/Taps/homebrew/{homebrew-core,homebrew-cask} (served via the API now)"
      read -r -p "Proceed? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || exit 1

      sudo rm -f "${brewPath}" "${repository}/Library/Homebrew"
      sudo rm -rf "${nixHomebrewMarker}" \
        "${repository}/Library/Taps/homebrew/homebrew-core" \
        "${repository}/Library/Taps/homebrew/homebrew-cask"

      ${installHomebrew}
      echo "Done. Run 'hms' to apply the declared Brewfile."
    '';
  };
in {
  imports = [inputs.home-manager-brew.homeManagerModules.default];

  homebrew = {
    enable = hostPlatform.isDarwin;
    inherit brewPath;
    ## brew's own auto-update (HOMEBREW_AUTO_UPDATE_SECS) keeps metadata fresh;
    ## no extra `brew update` on every switch
    update = false;
    ## Both replaced below: the module's cleanup doesn't zap, and its upgrade is
    ## `--greedy` (would force-upgrade self-updating casks like wacom-tablet)
    cleanup = false;
    upgrade = false;
  };

  home.activation = lib.mkIf hostPlatform.isDarwin {
    ## Same as the module's installer step, but defers to nix-homebrew on Intel
    ## and refuses to install over its leftovers elsewhere (the store-backed shim
    ## dangles once GC'd)
    homebrewInstall = lib.mkForce (lib.hm.dag.entryAfter ["installPackages" "linkGeneration"] (
      if brewFromNixDarwin
      then ''
        if [ ! -x "${brewPath}" ]; then
          warnEcho "Homebrew not found (${brewPath}); it's installed by nix-homebrew, run 'hts' first."
        fi
      ''
      else ''
        if [ -e "${nixHomebrewMarker}" ]; then
          warnEcho "Homebrew at ${prefix} is still nix-homebrew's shim; run 'brew-migrate-from-nix-homebrew' once."
        elif [ ! -x "${brewPath}" ]; then
          echo "Homebrew not found (${brewPath}), installing..."
          run ${installHomebrew}
        fi
      ''
    ));

    ## Matches nix-darwin's old onActivation.cleanup = "zap"
    homebrewBundleCleanupZap = lib.hm.dag.entryAfter ["homebrewBundleInstall"] ''
      if [ -x "${brewPath}" ]; then
        run "${brewPath}" bundle cleanup --file "${config.home.sessionVariables.HOMEBREW_BUNDLE_FILE}" --force --zap
      fi
    '';

    ## Matches nix-darwin's old onActivation.upgrade = true (non-greedy)
    homebrewUpgradeNonGreedy = lib.hm.dag.entryAfter ["homebrewBundleCleanupZap"] ''
      if [ -x "${brewPath}" ]; then
        run "${brewPath}" upgrade
      fi
    '';
  };

  home.sessionVariables = lib.mkIf hostPlatform.isDarwin {
    HOMEBREW_NO_ENV_HINTS = "1";
  };

  home.packages =
    lib.optionals hostPlatform.isDarwin [
      pkgs.customDarwin.zerobrew-bin
      (pkgs.writeShellScriptBin "brew-ultimate" ''
        echo "Running brew update..."
        brew update

        echo "Running brew upgrade..."
        brew upgrade

        echo "Running brew autoremove..."
        brew autoremove

        echo "Running brew cleanup..."
        brew cleanup -s --prune=0

        echo "Removing brew cache..."
        rm -rf "$(brew --cache)"

        echo "Brew maintenance complete!"
      '')
    ]
    ++ lib.optional (hostPlatform.isDarwin && !brewFromNixDarwin) brew-migrate-from-nix-homebrew;
}
