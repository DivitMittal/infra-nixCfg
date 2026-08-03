{
  config,
  pkgs,
  lib,
  ...
}:
with lib; {
  options.termux-gui = {
    enable = mkEnableOption "X11 GUI session via termux-x11 on Android/Termux";

    gpu = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install Mesa-Turnip and configure the GPU env (Vulkan via Turnip on
          Adreno, Zink as fallback). Requires `pkgs.custom.mesa-turnip` to
          have a real source pinned — until then this option will fail to
          build. Leave at `false` for an X11-only setup.
        '';
      };

      driver = mkOption {
        type = types.enum ["auto" "turnip" "zink" "swrast"];
        default = "auto";
        description = ''
          GPU driver to advertise to Mesa. `auto` picks `turnip` (the most
          common Android case); `zink` uses GL-on-Vulkan; `swrast` is the
          software fallback.
        '';
      };
    };
  };

  config = let
    cfg = config.termux-gui;
    # Resolve `auto` to a concrete driver by reading the option at eval time --
    # the actual on-device detection happens in `gpu-detect` at runtime.
    mesaDriver =
      {
        auto = "freedreno"; # Adreno is by far the most common Android GPU
        turnip = "freedreno";
        zink = "zink";
        swrast = "llvmpipe";
      }.${
        cfg.gpu.driver
      };
  in
    mkIf cfg.enable {
      environment.packages = lib.attrsets.attrValues (
        {
          # Fonts so X11 apps render text without falling back to tofu
          inherit
            (pkgs)
            noto-fonts
            dejavu_fonts
            liberation_ttf
            ;
          nerd-fonts-caskaydia-cove = pkgs.nerd-fonts.caskaydia-cove;
        }
        // lib.optionalAttrs cfg.gpu.enable {
          # Prebuilt Mesa with Turnip + Zink (placeholder URL — see package.nix)
          inherit (pkgs.custom) mesa-turnip;
        }
        // {
          # Launcher scripts (all on $PATH).
          #
          # `termux-x11` itself is **not** a Nix package — it's an Android app
          # plus a Termux-side launcher, both installed from x11-repo. On the
          # Nix side we only provide the glue scripts. Run once on the phone:
          #
          #   pkg install x11-repo
          #   pkg install termux-x11
          #
          # then `x11-start xclock` will work.
          x11-start = pkgs.writeShellScriptBin "x11-start" ''
            #!${pkgs.runtimeShell}
            set -euo pipefail

            if ! command -v termux-x11 >/dev/null 2>&1; then
              echo "x11-start: termux-x11 not found on PATH." >&2
              echo "  Install it with:  pkg install x11-repo && pkg install termux-x11" >&2
              exit 1
            fi

            pidfile="$HOME/.cache/termux-x11.pid"
            if [[ ! -f "$pidfile" ]] || ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
              termux-x11 :1 &
              echo $! > "$pidfile"
              # Give the server a moment to come up
              sleep 0.5
            fi

            export DISPLAY=:1
            exec "$@"
          '';

          x11-app = pkgs.writeShellScriptBin "x11-app" ''
            #!${pkgs.runtimeShell}
            set -euo pipefail
            export DISPLAY="''${DISPLAY:-:1}"
            exec "$@"
          '';

          gpu-detect = pkgs.writeShellScriptBin "gpu-detect" ''
            #!${pkgs.runtimeShell}
            # Print the resolved GPU driver: turnip | zink | swrast
            if grep -qi adreno /proc/cpuinfo 2>/dev/null; then
              echo turnip
            elif [ -e /dev/dri/renderD128 ] || [ -e /dev/dri/card0 ]; then
              echo zink
            else
              echo swrast
            fi
          '';

          gpu-env = pkgs.writeShellScriptBin "gpu-env" ''
            #!${pkgs.runtimeShell}
            # Print `export KEY=VALUE` lines for the resolved driver.
            # Usage: eval "$(gpu-env)" && x11-start glxinfo
            driver="''${1:-$(gpu-detect)}"
            case "$driver" in
              turnip)
                echo 'export MESA_LOADER_DRIVER_OVERRIDE=freedreno'
                echo 'export TU_DEBUG=noub'
                echo 'export GALLIUM_DRIVER=freedreno'
                ;;
              zink)
                echo 'export MESA_LOADER_DRIVER_OVERRIDE=zink'
                echo 'export GALLIUM_DRIVER=zink'
                ;;
              swrast)
                echo 'export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe'
                echo 'export GALLIUM_DRIVER=llvmpipe'
                ;;
              *)
                echo "gpu-env: unknown driver: $driver" >&2
                exit 1
                ;;
            esac
          '';
        }
      );

      environment.sessionVariables =
        {
          DISPLAY = ":1";
          XDG_RUNTIME_DIR = "${config.user.home}/.xdg";
        }
        // lib.optionalAttrs cfg.gpu.enable {
          MESA_LOADER_DRIVER_OVERRIDE = mesaDriver;
        };

      build.activation.gui-setup =
        ''
          $DRY_RUN_CMD mkdir $VERBOSE_ARG -p \
            "${config.user.home}/.X11-unix" \
            "${config.user.home}/.xdg" \
            "${config.user.home}/.cache"
        ''
        + lib.optionalString cfg.gpu.enable ''
          # Drop a Vulkan ICD manifest for Turnip into the user's local dir.
          $DRY_RUN_CMD mkdir $VERBOSE_ARG -p \
            "${config.user.home}/.local/share/vulkan/icd.d"
          cat > "${config.user.home}/.local/share/vulkan/icd.d/freedreno.json" <<EOF
          {
            "ICD": {
              "library_path": "${pkgs.custom.mesa-turnip}/lib/libvulkan_freedreno.so"
            }
          }
          EOF
        '';
    };
}
