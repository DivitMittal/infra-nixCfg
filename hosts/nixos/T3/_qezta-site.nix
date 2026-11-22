# Static qezta.com build. Not a module: the leading underscore keeps
# import-tree from evaluating it. qezta-endpoints.nix imports it.
#
# Qezta/site exports no package. The lockfile is pnpm 9.0, fetched with this
# nixpkgs' pnpm (11.9.0 when the hash was taken, fetcherVersion 3).
{
  pkgs,
  src,
}:
pkgs.stdenv.mkDerivation {
  pname = "qezta-site";
  version = "0.0.1";
  inherit src;

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.pnpmConfigHook
    pkgs.pnpm
  ];

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit src;
    pname = "qezta-site";
    version = "0.0.1";
    inherit (pkgs) pnpm;
    fetcherVersion = 3;
    hash = "sha256-TfzYZ2JocnvBoH32wFuoFSVPC2fbV4ifJRIimrBIQyM=";
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
    pnpm run build
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
