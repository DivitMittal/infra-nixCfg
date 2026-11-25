# Fetch the locked packages by content hash so the actual site build is offline.
{
  pkgs,
  pname,
  src,
  lockfile,
  hashes,
}: let
  platform = pkgs.stdenv.hostPlatform;
  os =
    if platform.isDarwin
    then "darwin"
    else "linux";
  cpu =
    if platform.isAarch64
    then "arm64"
    else "x64";
in
  pkgs.runCommand "${pname}-bun-deps-${platform.system}" {
    nativeBuildInputs = [pkgs.bun pkgs.cacert];
    impureEnvVars = pkgs.lib.fetchers.proxyImpureEnvVars;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = hashes.${platform.system};
  } ''
    export HOME="$TMPDIR"
    cp ${src}/package.json package.json
    cp ${lockfile} bun.lock
    bun install --frozen-lockfile --ignore-scripts --linker=hoisted --backend=copyfile \
      --os=${os} --cpu=${cpu}
    # Bun skips git deps whose lock entry lacks an integrity value.
    test -f node_modules/@qezta/ui/package.json
    mv node_modules "$out"
  ''
