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
      x86_64-linux = "sha256-g34U4UJ7MDgIZwUQ2f//PxfVUrcJyfZhU75niPscsCE=";
      x86_64-darwin = "sha256-ouj0hGPynxSKFDwtA+paz0oZQv4xrY8bexcIrrne0Q4=";
    };
  };

  postPatch = ''
    substituteInPlace svelte.config.js \
      --replace-fail 'adapter: adapter({ precompress: true })' 'adapter: adapter({ precompress: true }),
    paths: { relative: true }'
    substituteInPlace src/app.html \
      --replace-fail 'href="/favicon.ico"' 'href="favicon.ico"' \
      --replace-fail 'href="/cursor_trail_vertex.glsl"' 'href="cursor_trail_vertex.glsl"' \
      --replace-fail 'href="/cursor_trail_fragment.glsl"' 'href="cursor_trail_fragment.glsl"' \
      --replace-fail 'src="/cursor_trail.js"' 'src="cursor_trail.js"'
    substituteInPlace src/routes/+page.svelte \
      --replace-fail 'const logoSrc = "/qezta.gif";' 'const logoSrc = "qezta.gif";'
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
