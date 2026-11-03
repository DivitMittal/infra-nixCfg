{
  lib,
  stdenvNoCC,
  python3,
  rage,
  sources,
}: let
  googleClientId = builtins.getEnv "GOOGLE_CLIENT_ID";
  googleClientSecret = builtins.getEnv "GOOGLE_CLIENT_SECRET";
in
  stdenvNoCC.mkDerivation {
    pname = "mutt-oauth2";
    version = sources.mutt.version;

    dontUnpack = true;

    nativeBuildInputs = [python3];

    buildPhase = ''
      ${python3}/bin/python3 - <<PYEOF
      import re

      with open("${sources.mutt.src}/contrib/mutt_oauth2.py") as f:
          content = f.read()

      # Patch Microsoft client_id with Thunderbird's production app ID
      content = re.sub(
          r"('microsoft'[^}]*?'client_id':\s*)'[^']*'",
          r"\g<1>'9e5f94bc-e8a4-4e73-b8be-63364c29d753'",
          content,
          flags=re.DOTALL
      )

      # Patch Google credentials with personal GCP credentials
      content = re.sub(
          r"('google'[^}]*?'client_id':\s*)'[^']*'",
          r"\g<1>'${googleClientId}'",
          content,
          flags=re.DOTALL
      )
      content = re.sub(
          r"('google'[^}]*?'client_secret':\s*)'[^']*'",
          r"\g<1>'${googleClientSecret}'",
          content,
          flags=re.DOTALL
      )

      # Patch encryption/decryption pipes to use rage with a dedicated age identity
      rage = "${rage}/bin/rage"
      identity = "str(Path('~/.local/share/oauth2/identity.key').expanduser())"
      content = content.replace(
          "ENCRYPTION_PIPE = ['gpg', '--encrypt', '--recipient', 'YOUR_GPG_IDENTITY']",
          f"ENCRYPTION_PIPE = ['{rage}', '-e', '-i', {identity}]"
      )
      content = content.replace(
          "DECRYPTION_PIPE = ['gpg', '--decrypt']",
          f"DECRYPTION_PIPE = ['{rage}', '-d', '-i', {identity}]"
      )

      with open("mutt_oauth2_patched.py", "w") as f:
          f.write(content)
      PYEOF
    '';

    installPhase = ''
      mkdir -p $out/bin $out/libexec
      cp mutt_oauth2_patched.py $out/libexec/mutt_oauth2.py
      cat > $out/bin/oauth2 <<EOF
      #!/bin/sh
      exec ${python3}/bin/python3 $out/libexec/mutt_oauth2.py "\$@"
      EOF
      chmod +x $out/bin/oauth2
    '';

    meta = {
      # Microsoft: Thunderbird's production app ID (public, uses PKCE — no secret needed):
      #   https://hg.mozilla.org/comm-central/file/tip/mailnews/base/src/OAuth2Providers.sys.mjs
      # Google: confidential client — register at https://console.cloud.google.com
      #   Enable: Gmail API. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET before building.
      description = "mutt_oauth2.py patched with Microsoft/Google credentials and rage encryption";
      license = lib.licenses.gpl2Plus;
      mainProgram = "oauth2";
      platforms = lib.platforms.unix;
    };
  }
