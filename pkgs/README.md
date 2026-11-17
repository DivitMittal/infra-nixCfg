# Packages Directory

Custom package definitions maintained outside of nixpkgs for platform-specific tooling.

## Structure

```
pkgs/
├── custom/       # Custom derivations
├── darwin/       # macOS-specific packages
```

## Package Types

- Software not in nixpkgs
- Custom/patched versions
- Binary packages
- Platform-specific apps

## Basic Package

```nix
{lib, stdenv, fetchFromGitHub}:
stdenv.mkDerivation rec {
  pname = "mytool";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "user";
    repo = "mytool";
    rev = "v${version}";
    sha256 = "...";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp mytool $out/bin/
  '';

  meta = with lib; {
    description = "Tool description";
    license = licenses.mit;
  };
}
```

## Usage

Via overlays:

```nix
pkgs.mytool  # Auto-exposed
```

Or direct:

```nix
pkgs.callPackage ../pkgs/custom/mytool {}
```

## Testing

```bash
nix build .#mypackage
nix run .#mypackage
```
