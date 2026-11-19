#!/usr/bin/env bash
# Maps changed file paths (one per line on stdin) to the eval targets they can
# affect. Prints one of:
#   ALL        evaluate every target
#   <regex>    evaluate targets whose attr matches (e.g. ^nixosConfigurations\.T1\.)
#   (nothing)  no eval target is affected
#
# The map mirrors how flake/mkCfg.nix and the host enums assemble each class.
# Anything not listed falls back to ALL, so a missing rule costs CI time, never
# coverage. Pushes to master always evaluate everything regardless.
set -euo pipefail

nixos='^nixosConfigurations\.'
darwin='^darwinConfigurations\.'
home='^homeConfigurations\.'
iso='^nixosConfigurations\.(iso|l1n-iso|as-iso)\.'
homelab='^nixosConfigurations\.(T1|T2|T3|MON1)\.'

patterns=()
add() { patterns+=("$1"); }

while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
  # Not part of any evaluated configuration. flake-check still covers the
  # outputs these define (deploy nodes, devshells, topology, droid/android).
  *.md | *.adoc | docs/* | openspec/* | utils/* | .github/* | .git* | .claude/* | .serena/*) ;;
  hosts/droid/* | common/hosts/droid/* | common/hosts/droid-launcher/*) ;;
  android/* | flake/android.nix) ;;
  hosts/switch/* | hosts/deploy.nix) ;;
  flake/devshells.nix | flake/formatters.nix | flake/checks.nix | flake/topology.nix) ;;
  hosts/win/* | common/hosts/win/* | flake/mkWinCfg.nix) ;;

  # One class.
  common/home/* | home/* | modules/home/* | assets/*) add "$home" ;;
  common/hosts/darwin/* | modules/hosts/darwin/* | hosts/darwin/enum.nix) add "$darwin" ;;
  common/hosts/nixos/*) add "$nixos" ;; # iso hosts are nixosConfigurations too
  common/hosts/all/*) add "$nixos" && add "$darwin" ;;
  common/hosts/iso/* | hosts/iso/enum.nix) add "$iso" ;;
  common/hosts/netboot/* | hosts/netboot/*) add '^nixosConfigurations\.t1-netboot\.' ;;
  hosts/nixos/enum.nix) add "$nixos" ;;

  # One host, plus the hosts that import it.
  hosts/nixos/_homelab/*) add "$homelab" ;;
  # T1 boots the T640 router image these build.
  hosts/openwrt/* | flake/openwrt*.nix) add '^nixosConfigurations\.T1\.' ;;
  # ASL1 imports L1's defaults, programs and services.
  hosts/darwin/L1/*) add '^darwinConfigurations\.(L1|ASL1)\.' ;;
  hosts/nixos/*/* | hosts/darwin/*/* | hosts/iso/*/*)
    host=$(cut -d/ -f3 <<<"$f")
    class=$(cut -d/ -f2 <<<"$f")
    case "$class" in
    darwin) add "^darwinConfigurations\\.${host}\\." ;;
    *) add "^nixosConfigurations\\.${host}\\." ;;
    esac
    ;;

  # flake.nix, flake.lock, mkCfg, lib, overlays, pkgs, common/all, CI itself,
  # and anything new.
  *)
    echo ALL
    exit 0
    ;;
  esac
done

[ "${#patterns[@]}" -eq 0 ] && exit 0
printf '%s\n' "${patterns[@]}" | sort -u | paste -sd'|' -
