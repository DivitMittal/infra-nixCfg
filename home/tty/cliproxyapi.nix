{
  config,
  lib,
  pkgs,
  ...
}: let
  configPath = "${config.xdg.configHome}/cliproxyapi/config.yaml";
  openrouterKeyPath = config.age.secrets."ai/openrouter.age".path;
  yamlPatcher = pkgs.python3.withPackages (ps: [ps.pyyaml]);

  # cliproxyapi's own mutable-settings merge (ai-nixCfg's
  # cliproxyapiSettingsActivation) replaces `openai-compatibility` wholesale
  # from the Nix-declared default on *every* activation, so the OpenRouter
  # api-key-entries it ships (deliberately empty, to keep secrets out of the
  # Nix store) get wiped back to empty each time too. Patch the real key back
  # in immediately after, reading it from the agenix-decrypted runtime path —
  # never through a Nix-evaluated value, so it never touches the store.
  patchOpenrouterKey = ''
    ${yamlPatcher}/bin/python - ${lib.escapeShellArg configPath} ${lib.escapeShellArg openrouterKeyPath} <<'PY'
    import pathlib
    import sys

    import yaml

    config_path = pathlib.Path(sys.argv[1])
    key_path = pathlib.Path(sys.argv[2])

    if not config_path.exists() or not key_path.exists():
        sys.exit(0)

    key = key_path.read_text().strip()
    if not key:
        sys.exit(0)

    data = yaml.safe_load(config_path.read_text()) or {}
    for provider in data.get("openai-compatibility", []):
        if provider.get("name") == "openrouter":
            provider["api-key-entries"] = [{"api-key": key}]

    config_path.write_text(yaml.safe_dump(data, sort_keys=False))
    PY
  '';
in {
  home.activation.cliproxyapiOpenrouterKey =
    lib.hm.dag.entryAfter ["cliproxyapiSettingsActivation"] patchOpenrouterKey;
}
