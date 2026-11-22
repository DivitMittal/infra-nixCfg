## Lan Mouse on L2's Windows boot: its half of the desk in lib/lan-mouse.nix.
## The login task and firewall rule come from ./desk.nix.
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  desk = import (self + "/lib/lan-mouse.nix") {inherit lib;};
  spec = desk.windows.L2;
  release = (pkgs.callPackage (self + "/pkgs/_sources/generated.nix") {}).lan-mouse-windows-x86_64;
  # The release bundles lan-mouse.exe with the GTK DLLs it loads at start.
  package = pkgs.runCommand "lan-mouse-windows-${release.version}" {nativeBuildInputs = [pkgs.unzip];} ''
    mkdir -p $out/bin
    unzip -q ${release.src} -d $out/bin
  '';
  configFile = (pkgs.formats.toml {}).generate "lan-mouse-config.toml" spec.config;
  home = "C:\\Users\\${config.win.user.name}";
  directory = "${home}\\AppData\\Local\\lan-mouse";
in {
  # %LOCALAPPDATA%\lan-mouse\bin, next to the config, log and certificate.
  win.packages.lan-mouse.package = package;

  # Under "home", not "appdata-local": nix-win copies the files tree into the
  # toplevel before win.packages, read-only, and that second copy then fails
  # silently on any root both trees share. nix-win's own Windows Terminal
  # module places AppData files the same way.
  win.files."AppData/Local/lan-mouse/config.toml".source = configFile;

  desk.daemons.${spec.task.name} = {
    executable = "${home}\\${spec.executable}";
    arguments = ''-c "${directory}\config.toml" daemon'';
    log = "${directory}\\daemon.log";
    processes = ["lan-mouse"];
    inherit (spec.task) runLevel restartCount restartIntervalMinutes;
  };
}
