{
  lib,
  stdenvNoCC,
  sources,
  fetchurl,
  python3,
  xz,
}: let
  # Sparkle version/hash mirror upstream's scripts/fetch-sparkle.sh pin, so the
  # binary links the same framework the release DMG ships.
  sparkle = fetchurl {
    url = "https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-2.9.5.tar.xz";
    sha256 = "015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc";
  };
  arch = stdenvNoCC.hostPlatform.darwinArch;
  target = "${arch}-apple-macos14.0";
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "Crisp";
    version = lib.removePrefix "v" sources.Crisp.version;
    inherit (sources.Crisp) src;

    nativeBuildInputs = [python3 xz];

    # nixpkgs' swift is 5.10 and Crisp needs Swift 6 plus the macOS 26 SDK
    # (NSGlassEffectView), so compile with the host's Command Line Tools.
    # Works because darwin builds here run unsandboxed; __noChroot keeps it
    # working under sandbox = relaxed.
    __noChroot = true;

    # Stripping would invalidate the ad-hoc code signatures written below.
    dontStrip = true;

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR"
      # Drop the nixpkgs SDK/toolchain env so xcrun resolves the system CLT.
      swiftc() {
        env -u SDKROOT -u DEVELOPER_DIR -u MACOSX_DEPLOYMENT_TARGET \
          /usr/bin/xcrun --sdk macosx swiftc \
          -module-cache-path "$TMPDIR/swift-module-cache" "$@"
      }

      mkdir -p vendor/Sparkle
      tar -xJf ${sparkle} -C vendor/Sparkle ./Sparkle.framework

      # Flags mirror upstream scripts/release.sh (minus the Xcode-only
      # Shortcuts/AppIntents metadata), built for the host arch only.
      find Crisp -name '*.swift' | sort > sources.txt
      swiftc -O -swift-version 6 -parse-as-library -target ${target} \
        -import-objc-header Crisp/Crisp-Bridging-Header.h \
        -F vendor/Sparkle -framework Sparkle \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -Xlinker -U -Xlinker _SLSConfigureDisplayEnabled \
        -Xlinker -U -Xlinker _SLSGetDisplayList \
        -Xlinker -U -Xlinker _SLSSetDisplayRotation \
        $(cat sources.txt) -o Crisp-bin

      # crispctl: top-level main.swift, so no -parse-as-library.
      swiftc -O -swift-version 6 -target ${target} \
        Sources/crispctl/*.swift \
        Crisp/Models/CrispControlModel.swift Crisp/Models/BrightnessKeySteps.swift \
        -o crispctl-bin

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      app="$out/Applications/Crisp.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks" "$out/bin"

      install -m755 Crisp-bin "$app/Contents/MacOS/Crisp"
      install -m755 crispctl-bin "$app/Contents/MacOS/crispctl"
      ln -s "$app/Contents/MacOS/crispctl" "$out/bin/crispctl"

      # Crisp isn't sandboxed, so Sparkle's XPC services are unused (upstream strips them too).
      cp -R vendor/Sparkle/Sparkle.framework "$app/Contents/Frameworks/"
      rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
             "$app/Contents/Frameworks/Sparkle.framework/XPCServices"

      iconset="$TMPDIR/AppIcon.iconset"
      icons=Crisp/Assets.xcassets/AppIcon.appiconset
      mkdir -p "$iconset"
      for pair in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 \
                  256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
        cp "$icons/icon_''${pair%%:*}.png" "$iconset/icon_''${pair#*:}.png"
      done
      /usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

      langs=$(python3 scripts/xcstrings-compile.py Crisp/Resources/Localizable.xcstrings "$app/Contents/Resources")
      locXml=""
      for l in $langs; do locXml="$locXml<string>$l</string>"; done

      printf 'APPL????' > "$app/Contents/PkgInfo"
      # Same Info.plist as upstream release.sh, except Sparkle's automatic
      # update checks are off: a store path can't be updated in place, so
      # upgrades come from bumping the nvfetcher source instead.
      cat > "$app/Contents/Info.plist" <<PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleName</key><string>Crisp</string>
        <key>CFBundleDisplayName</key><string>Crisp</string>
        <key>CFBundleIdentifier</key><string>com.crisp.app</string>
        <key>CFBundleExecutable</key><string>Crisp</string>
        <key>CFBundleIconFile</key><string>AppIcon</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
        <key>CFBundleDevelopmentRegion</key><string>en</string>
        <key>CFBundleLocalizations</key><array>$locXml</array>
        <key>CFBundleShortVersionString</key><string>${finalAttrs.version}</string>
        <key>CFBundleVersion</key><string>${finalAttrs.version}</string>
        <key>LSMinimumSystemVersion</key><string>14.0</string>
        <key>LSUIElement</key><true/>
        <key>NSHumanReadableCopyright</key><string>Crisp - Free &amp; Open Source</string>
        <key>NSAppleEventsUsageDescription</key><string>Crisp uses System Events to switch Dark Mode with the system's animated transition.</string>
        <key>SUFeedURL</key><string>https://crispmac.app/appcast.xml</string>
        <key>SUPublicEDKey</key><string>3UT7wZoXDzrAhwCMVS3DoPt2lcya9H/cvlyXliuPuhM=</string>
        <key>SUEnableAutomaticChecks</key><false/>
        <key>SUVerifyUpdateBeforeExtraction</key><true/>
        <key>SURequireSignedFeed</key><true/>
        <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
      </dict>
      </plist>
      PLIST

      # Ad-hoc sign inside-out without --deep, as upstream does.
      fw="$app/Contents/Frameworks/Sparkle.framework"
      for item in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw" "$app/Contents/MacOS/crispctl"; do
        /usr/bin/codesign --force --sign - "$item"
      done
      /usr/bin/codesign --force --sign - --entitlements Crisp/Crisp.entitlements "$app"
      /usr/bin/codesign --verify --deep --strict "$app"

      runHook postInstall
    '';

    meta = {
      description = "Menu bar display manager: HiDPI scaling, DDC brightness/volume, presets, virtual displays";
      homepage = "https://github.com/didriksg/Crisp";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      maintainers = with lib.maintainers; [DivitMittal];
      sourceProvenance = with lib.sourceTypes; [fromSource];
      mainProgram = "crispctl";
    };
  })
