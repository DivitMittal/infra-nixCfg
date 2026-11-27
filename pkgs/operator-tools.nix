{pkgs}: let
  inherit (pkgs) lib stdenv;
  platform = stdenv.hostPlatform;

  rustTool = {
    owner ? "manic-systems",
    pname,
    rev,
    hash,
    meta,
    ...
  } @ args:
    pkgs.rustPlatform.buildRustPackage ((removeAttrs args ["owner" "rev" "hash"])
      // {
        src = pkgs.fetchFromGitHub {
          inherit owner rev hash;
          repo = pname;
        };
        meta =
          meta
          // {
            homepage = "https://github.com/${owner}/${pname}";
            mainProgram = pname;
          };
      });
in {
  nixploit =
    # Needs rustc >= 1.98.1, newer than the 26.05 pin used on Intel Darwin.
    if lib.versionAtLeast pkgs.rustc.version "1.98.1"
    then
      rustTool {
        pname = "nixploit";
        version = "0.1.0-unstable-2026-11-07";
        rev = "bf0698f5981d0126655ee9f41d845c05706fc390";
        hash = "sha256-JwW9tmHvCXsi2SY4soAQoQLnjs2V70+r8q/oob/aFB8=";
        cargoHash = "sha256-pWqkgAmAGWIJtPZ5ZCidgtbxLRFvNUAT2nGHqxQtfi0=";
        nativeBuildInputs = [pkgs.pkg-config];
        buildInputs = [pkgs.sqlite];
        cargoBuildFlags = ["--ignore-rust-version"];
        cargoTestFlags = ["--ignore-rust-version"];
        meta = {
          description = "Scan Nix closures for known vulnerabilities";
          license = lib.licenses.eupl12;
        };
      }
    else null;

  nixtopsy =
    if platform.isLinux || platform.isDarwin
    then
      rustTool {
        pname = "nixtopsy";
        version = "0.1.1";
        rev = "752c14876ee14cb47bab5c72024f2377caddf425";
        hash = "sha256-9bRgcG72LFGjlD5HyODxUd5Fo9YrnUdbIrixc90DZjU=";
        cargoHash = "sha256-OL5Hrz9tpf0iwbcxavoydw6ImoIf5Aiu9B7ARc9vRnw=";
        meta = {
          description = "Interactively dissect Nix closures";
          license = lib.licenses.mit;
        };
      }
    else null;

  rom =
    # Upstream does not advertise Intel Darwin builds.
    if builtins.elem platform.system ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
    then
      rustTool {
        pname = "rom";
        version = "0.6.1";
        rev = "243f994c06a760e1efdbed632306c7ea5e82c212";
        hash = "sha256-KRYqHqIOlfcpkxDTQJT7FDlmNpucexRlgWF24AvajuI=";
        cargoHash = "sha256-XcFgDZQQGY9HMGEf6K8RSEOS5bRcjo4wdWIrlbMOhtw=";
        meta = {
          description = "Visual build output monitor for Nix";
          license = lib.licenses.eupl12;
        };
      }
    else null;
}
