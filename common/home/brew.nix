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
  ## Left behind by nix-homebrew (the old nix-darwin-side installer)
  nixHomebrewMarker = "${repository}/Library/.homebrew-is-managed-by-nix";

  brew-migrate-from-nix-homebrew = pkgs.writeShellApplication {
    name = "brew-migrate-from-nix-homebrew";
    runtimeInputs = [pkgs.curl];
    text = ''
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

      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
    ## Same as the module's installer step, but refuses to install over
    ## nix-homebrew's leftovers (the store-backed shim dangles once GC'd)
    homebrewInstall = lib.mkForce (lib.hm.dag.entryAfter ["installPackages" "linkGeneration"] ''
      if [ -e "${nixHomebrewMarker}" ]; then
        warnEcho "Homebrew at ${prefix} is still nix-homebrew's shim; run 'brew-migrate-from-nix-homebrew' once."
      elif [ ! -x "${brewPath}" ]; then
        echo "Homebrew not found (${brewPath}), installing..."
        run ${pkgs.bash}/bin/bash -c "$(${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
    '');

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

  home.packages = lib.optionals hostPlatform.isDarwin [
    pkgs.customDarwin.zerobrew-bin
    brew-migrate-from-nix-homebrew
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
  ];
}
