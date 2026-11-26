# Static qezta.com build. Not a module: the leading underscore keeps
# import-tree from evaluating it. qezta-endpoints.nix imports it.
#
# The adjacent Bun lockfile was migrated from the pinned upstream lock.
{
  pkgs,
  src,
}:
pkgs.stdenv.mkDerivation {
  pname = "qezta-site";
  version = "0.0.1";
  inherit src;

  nativeBuildInputs = [pkgs.bun pkgs.nodejs];

  bunDeps = import ./_bun-site-deps.nix {
    inherit pkgs src;
    pname = "qezta-site";
    lockfile = ./_qezta-site.bun.lock;
    hashes = {
      x86_64-linux = "sha256-ZVFGj9l7m+bYy23yniYLvfAej6iVuD/68SA2K1+N+dI=";
      x86_64-darwin = "sha256-ouj0hGPynxSKFDwtA+paz0oZQv4xrY8bexcIrrne0Q4=";
    };
  };

  postPatch = ''
    substituteInPlace svelte.config.js \
      --replace-fail 'adapter: adapter({ precompress: true })' 'adapter: adapter({ precompress: true }),
    paths: { relative: true }'
    substituteInPlace src/routes/+layout.svelte \
      --replace-fail "import { injectAnalytics } from '@vercel/analytics/sveltekit';" "" \
      --replace-fail "import { injectSpeedInsights } from '@vercel/speed-insights/sveltekit';" "" \
      --replace-fail 'injectSpeedInsights();' "" \
      --replace-fail 'injectAnalytics();' ""
  '';

  buildPhase = ''
    runHook preBuild
    cp -R "$bunDeps" node_modules
    chmod -R u+w node_modules
    patchShebangs node_modules
    bun run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    test -f build/index.html
    test -d build/_app
    if grep -R -q -E '@vercel/analytics|va.vercel-scripts.com|speed-insights' build; then
      echo "vercel telemetry still in the build" >&2
      exit 1
    fi
    if grep -R -q -E 'src="/_app/|href="/_app/' build; then
      echo "absolute /_app asset paths remain" >&2
      exit 1
    fi
    mkdir -p "$out"
    cp -a build/. "$out/"
    runHook postInstall
  '';
}
