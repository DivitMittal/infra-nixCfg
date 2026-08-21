{
  lib,
  stdenv,
  sources,
}:
stdenv.mkDerivation (_finalAttrs: {
  pname = "menubar-dock";
  version = lib.removePrefix "v" sources.menubar-dock.version;
  inherit (sources.menubar-dock) src;

  # The upstream project was authored for Xcode IDE only and requires a few
  # fixups to build from the CLI:
  # 1. Set DEVELOPER_DIR to full Xcode (CommandLineTools alone has no xcodebuild);
  #    xcode-select defaults to the CLT, so probe /Applications/Xcode.app and
  #    versioned /Applications/Xcode-*.app first. Mirrors `ccs-bar`'s approach
  #    of unsetting the apple-sdk's stale DEVELOPER_DIR/SDKROOT.
  # 2. Strip the CocoaPods integration: the Podfile declares zero pods, but
  #    the project still has `[CP] Check Pods Manifest.lock` build phases,
  #    `baseConfigurationReference = ...Pods-*.xcconfig`, and `Pods_*.framework`
  #    link references that all require `pod install` to satisfy. Done with
  #    `sed` directly on project.pbxproj instead of a helper script, and a
  #    fresh shared scheme is written to replace the broken one.
  # 3. Inject SUPPORTED_PLATFORMS = macosx; everywhere — the project predates
  #    Xcode 14+'s stricter scheme validation, which rejects schemes whose
  #    buildables have no supported platforms declared.
  postPatch = ''
        unset DEVELOPER_DIR SDKROOT

        find_xcode_developer_dir() {
          if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
            echo /Applications/Xcode.app/Contents/Developer
            return 0
          fi
          for d in /Applications/Xcode-*/Contents/Developer; do
            if [[ -x "$d/usr/bin/xcodebuild" ]]; then
              echo "$d"
              return 0
            fi
          done
          return 1
        }

        if dev="$(find_xcode_developer_dir)"; then
          export DEVELOPER_DIR="$dev"
        else
          export DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
        fi

        if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
          echo "xcodebuild not found under '$DEVELOPER_DIR'." >&2
          echo "Install full Xcode (not just CommandLineTools) or set xcode-select." >&2
          exit 1
        fi

        pbxproj="MenuBarDock.xcodeproj/project.pbxproj"

        # - drop the `[CP] Check Pods Manifest.lock` build-phase reference and its
        #   orphaned PBXShellScriptBuildPhase block (needs `pod install` output)
        # - drop baseConfigurationReference lines pointing at Pods-*.xcconfig
        # - drop PBXBuildFile/PBXFileReference entries and list refs for
        #   Pods_*.framework (the CocoaPods umbrella framework wrappers)
        # - inject SUPPORTED_PLATFORMS + a clang++-driver LD into every
        #   buildSettings block (Xcode 26 rejects schemes without either)
        sed -E -i \
          -e '/[A-F0-9]{24} \/\* \[CP\] Check Pods Manifest\.lock \*\/,/d' \
          -e '/[A-F0-9]{24} \/\* \[CP\] Check Pods Manifest\.lock \*\/ = \{/,/^\t\t\};$/d' \
          -e '/baseConfigurationReference = [A-F0-9]{24} \/\* Pods-[^ ]+\.xcconfig \*\//d' \
          -e '/[A-F0-9]{24} \/\* Pods_[A-Za-z]+\.framework in Frameworks \*\/ = \{isa = PBXBuildFile;/d' \
          -e '/[A-F0-9]{24} \/\* Pods_[A-Za-z]+\.framework \*\/ = \{isa = PBXFileReference;/d' \
          -e '/[A-F0-9]{24} \/\* Pods_[A-Za-z]+\.framework( in Frameworks)? \*\/,/d' \
          -e 's/buildSettings = \{/buildSettings = {\n\t\t\t\tSUPPORTED_PLATFORMS = macosx;\n\t\t\t\tLD = "$(DT_TOOLCHAIN_DIR)\/usr\/bin\/clang++";/' \
          "$pbxproj"

        # The shared scheme (`Menu Bar Dock.xcscheme`) references "Menu Bar Dock"
        # / "Menu Bar Dock.xcodeproj" — names that don't match the actual target
        # (`MenuBarDock`) or project (`MenuBarDock.xcodeproj`). Xcode 26 rejects
        # this as "scheme not configured for the build action". Replace it with
        # a working scheme that targets `MenuBarDock`.
        scheme_dir="MenuBarDock.xcodeproj/xcshareddata/xcschemes"
        mkdir -p "$scheme_dir"
        cat >"$scheme_dir/MenuBarDock.xcscheme" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme
       LastUpgradeVersion = "2620"
       version = "1.3">
       <BuildAction
          parallelizeBuildables = "YES"
          buildImplicitDependencies = "YES">
          <BuildActionEntries>
             <BuildActionEntry
                buildForTesting = "YES"
                buildForRunning = "YES"
                buildForProfiling = "YES"
                buildForArchiving = "YES"
                buildForAnalyzing = "YES">
                <BuildableReference
                   BuildableIdentifier = "primary"
                   BlueprintIdentifier = "38412EFB222B3E2F00D3FA0C"
                   BuildableName = "MenuBarDock.app"
                   BlueprintName = "MenuBarDock"
                   ReferencedContainer = "container:MenuBarDock.xcodeproj">
                </BuildableReference>
             </BuildActionEntry>
          </BuildActionEntries>
       </BuildAction>
    </Scheme>
    EOF
  '';

  # Build the MenuBarDock target via the synthetic scheme written above.
  # The original shared scheme (`Menu Bar Dock.xcscheme`) references
  # "Menu Bar Dock" / "Menu Bar Dock.xcodeproj" — names that don't match the
  # actual target (`MenuBarDock`) or project (`MenuBarDock.xcodeproj`), so
  # Xcode 26 rejects it as "scheme not configured for the build action".
  #
  # We use `-derivedDataPath build` because Xcode's default DerivedData path
  # (`~/Library/Developer/Xcode/DerivedData/`) isn't writable in the nix
  # sandbox. `-derivedDataPath` requires `-scheme` (passing only `-target` is
  # rejected). The synthetic scheme written in postPatch targets the
  # MenuBarDock product by its real name.
  buildPhase = ''
    runHook preBuild

    arch="$(${stdenv.cc.targetPrefix}uname -m 2>/dev/null || uname -m)"
    case "$arch" in
      arm64|aarch64) host_arch=arm64 ;;
      *)             host_arch=x86_64 ;;
    esac

    /usr/bin/xcrun xcodebuild \
      -project MenuBarDock.xcodeproj \
      -scheme MenuBarDock \
      -configuration Release \
      -sdk macosx \
      -arch "$host_arch" \
      ONLY_ACTIVE_ARCH=NO \
      -derivedDataPath build \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      build

    runHook postBuild
  '';

  dontFixup = true;

  installPhase = ''
    runHook preInstall

    # xcodebuild with `-derivedDataPath build` writes the .app to
    # `build/Build/Products/Release/<Name>.app`.
    src="$PWD/build/Build/Products/Release/MenuBarDock.app"
    [ -d "$src" ] || { echo "expected build output not found: $src" >&2; exit 1; }

    dst="$out/Applications/MenuBarDock.app"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
  '';

  meta = {
    description = "macOS dock of running/pinned apps in the menu bar — fork with notification badges";
    homepage = "https://github.com/joaquinpiedracueva/menubar-dock";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    maintainers = with lib.maintainers; [DivitMittal];
    sourceProvenance = with lib.sourceTypes; [fromSource];
  };
})
