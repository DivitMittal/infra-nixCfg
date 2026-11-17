# Community extensions ported from a Raycast export, built from
# github:raycast/extensions source via vicinae's Raycast-compat shim
# (`inputs.vicinae.lib.<system>.mkRayCastExtension`, see ./setup.nix).
#
# `name` is each extension's package.json name (the id vicinae loads it
# under); `folder` is only set when it differs from the raycast/extensions
# checkout path. All pinned to the same upstream monorepo revision.
#
# Excluded: "screenocr" and "clean-keyboard" both compile their own Swift
# package via `ray build`'s swift-files plugin, which shells out to Swift
# Package Manager to resolve dependencies over the network — unavailable in
# Nix's build sandbox, so the build hangs (SPM's own DNS retries) and then
# fails. Would need SPM dependencies vendored (e.g. swiftpm2nix) to fix;
# not worth it for two extensions out of this set.
{
  rev = "4b4da7b2cdf53e61789fb5f7a3ddd92c68e5f8fa";

  extensions = [
    {
      name = "stock-tracker";
      hash = "sha256-fQc0bF41VOTiEXIv2G/uA1T/Mjc2WA6PyhgC0QKmv4E=";
    }
    {
      name = "glyph-search";
      hash = "sha256-zHbR5w1nLO288euH+xjVbnBI20HG4rBbGIdT+scgowY=";
    }
    {
      name = "restart-system-processes";
      hash = "sha256-mcgBHhXZrCIkOAX295UJE49h2zpD7KPNMWoM5El0dWo=";
    }
    {
      name = "onenote";
      hash = "sha256-6fSeX2Yb5QIksVMM8RvgKZGhjjdafVZ525qsVj89BGc=";
    }
    {
      name = "port-manager";
      hash = "sha256-JEFRI6228dyuW37OFSeQOe0VU6VhPN/NKgiD5PkXj2k=";
    }
    {
      name = "guitar-chords";
      hash = "sha256-pcftfMRlPSSpLIh0gLcVKD6G665E0ZTsf7OM1GAhdX0=";
    }
    {
      name = "open-with-app";
      hash = "sha256-HavqvJ6y6f/vH/sqBpiDKozavtzEYhyQFKTalyKZg1w=";
    }
    {
      name = "shortcuts-search";
      hash = "sha256-ZUuEgFugQ7j1DZFzwG32K505M5hpnqt7JMbFN4IuzUI=";
    }
    {
      # package.json name is "translate"; raycast/extensions folder is "google-translate"
      name = "translate";
      folder = "google-translate";
      hash = "sha256-YD06Eu7NpPx26EOOz5LXxCgpzOoMXjpAQ8rCrEXvJo8=";
    }
    {
      name = "installed-extensions";
      hash = "sha256-gi0r5BYtJv4hnOHTdVQH5+v26QbhFoW+LtOJgS2gPxM=";
    }
    {
      name = "password-generator";
      hash = "sha256-AtewnNow7ca7z4TwJyW0Mj5ZdYJiaIEQatbc22+9dG8=";
    }
    {
      name = "toothpick";
      hash = "sha256-5dG142RxMuSqShcmLkY348zKsNJCGhRBwck3hrO+4Nk=";
    }
    {
      name = "nixpkgs-search";
      hash = "sha256-ivazmD3e9qeJcUCJDDJaUXcmCNUm+9/3gpC6pVxhYNQ=";
    }
    {
      name = "gif-search";
      hash = "sha256-neenXhjjQ5Xayt/SPqq+Y3kPytWgOMZmKPfSn6BJN84=";
    }
    {
      name = "google-calendar";
      hash = "sha256-HfCBeObeux4HVLWgp+hy3u+A/CDJINlEByddGuMa8fA=";
    }
    {
      name = "notion";
      hash = "sha256-b3XxoEU+rxUU1khQj47a4fBgYbGpQ2TaWLTaRaN3hAs=";
    }
    {
      name = "music";
      hash = "sha256-d9MsjMlKPP7h3CdUeUv/t7Z5j2HeV3SoGxDDaBXbQ5w=";
    }
    {
      name = "spotify-player";
      hash = "sha256-5kghDipXrtmelkCE1EAKWt/PSr9apxPWtOkqNt6kX4U=";
    }
    {
      name = "audio-device";
      hash = "sha256-QboGEdzw0ZvNMrYBIrTb0qyMeAh08LMIzICV1p8jgAg=";
    }
    {
      name = "qr-code-scanner";
      hash = "sha256-wiMlX4XAtnfLqlnG4g7v3T+Wy0YLfWIpVvssZmOR8cM=";
    }
    {
      name = "snake";
      hash = "sha256-P7DFuv3sKX3GViLNDyrpc9+x6+uP6YiSv3tp52a3O8U=";
    }
    {
      name = "obsidian";
      hash = "sha256-BaKzu1vvwXmqvWpTJqb3sxTgs4XUkZj7tiQOZUW8Ew4=";
    }
    {
      name = "kill-process";
      hash = "sha256-PPnN5JhaGXSFsjZFwUDgV0eECHM9ygHIfsfte9Yk32Y=";
    }
  ];
}
