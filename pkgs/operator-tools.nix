{
  pkgs,
  # Override when the pinned nixpkgs rustc is too old (Intel Darwin uses 26.05).
  rustPlatform ? pkgs.rustPlatform,
}: let
  inherit (pkgs) lib;

  rustTool = {
    owner ? "manic-systems",
    pname,
    rev,
    hash,
    meta,
    ...
  } @ args:
    rustPlatform.buildRustPackage ((removeAttrs args ["owner" "rev" "hash"])
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
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
      });
in {
  nixploit = rustTool {
    pname = "nixploit";
    version = "0.1.0-unstable-2026-11-07";
    rev = "bf0698f5981d0126655ee9f41d845c05706fc390";
    hash = "sha256-JwW9tmHvCXsi2SY4soAQoQLnjs2V70+r8q/oob/aFB8=";
    cargoHash = "sha256-pWqkgAmAGWIJtPZ5ZCidgtbxLRFvNUAT2nGHqxQtfi0=";
    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.sqlite];
    meta = {
      description = "Scan Nix closures for known vulnerabilities";
      license = lib.licenses.eupl12;
    };
  };

  nixtopsy = rustTool {
    pname = "nixtopsy";
    version = "0.1.1";
    rev = "752c14876ee14cb47bab5c72024f2377caddf425";
    hash = "sha256-9bRgcG72LFGjlD5HyODxUd5Fo9YrnUdbIrixc90DZjU=";
    cargoHash = "sha256-OL5Hrz9tpf0iwbcxavoydw6ImoIf5Aiu9B7ARc9vRnw=";
    meta = {
      description = "Interactively dissect Nix closures";
      license = lib.licenses.mit;
    };
  };

  rom = rustTool {
    pname = "rom";
    version = "0.6.1";
    rev = "243f994c06a760e1efdbed632306c7ea5e82c212";
    hash = "sha256-KRYqHqIOlfcpkxDTQJT7FDlmNpucexRlgWF24AvajuI=";
    cargoHash = "sha256-XcFgDZQQGY9HMGEf6K8RSEOS5bRcjo4wdWIrlbMOhtw=";
    meta = {
      description = "Visual build output monitor for Nix";
      license = lib.licenses.eupl12;
    };
  };
}
