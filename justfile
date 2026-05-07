set shell := ["bash", "-euo", "pipefail", "-c"]

project := "teleport.xcodeproj"
scheme := "teleport"
app_name := "Teleport"
helper_name := "dev.x.teleport.PrivilegedHelper"
derived_data := "build/DerivedData"
dist_dir := "build/dist"
destination := "platform=macOS,arch=arm64"

# List available recipes
default:
    @just --list

# Remove build and packaging artifacts
clean:
    rm -rf {{derived_data}} {{dist_dir}}

# Build the app. Usage: just build [Debug|Release]
build configuration="Debug":
    xcodebuild \
      -project {{project}} \
      -scheme {{scheme}} \
      -configuration {{configuration}} \
      -destination '{{destination}}' \
      -derivedDataPath {{derived_data}} \
      build

# Build Debug
build-debug:
    just build Debug

# Build Release
build-release:
    just build Release

# Print the built .app path. Usage: just app-path [Debug|Release]
app-path configuration="Release":
    @echo "{{derived_data}}/Build/Products/{{configuration}}/{{app_name}}.app"

# Print the Release app version from the built bundle
version: build-release
    @/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '{{derived_data}}/Build/Products/Release/{{app_name}}.app/Contents/Info.plist'

# Build Release and create a versioned .app copy plus .dmg in build/dist
package: build-release
    #!/usr/bin/env bash
    set -euo pipefail

    APP="{{derived_data}}/Build/Products/Release/{{app_name}}.app"
    DIST="{{dist_dir}}"

    test -d "$APP"
    test -x "$APP/Contents/Resources/xray"
    test -x "$APP/Contents/Library/PrivilegedHelperTools/{{helper_name}}"

    VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
    BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
    PACKAGE_NAME="{{app_name}}-$VERSION-build-$BUILD"
    PACKAGE_APP="$DIST/$PACKAGE_NAME.app"
    DMG_ROOT="$DIST/dmg-root"
    PACKAGE_DMG="$DIST/$PACKAGE_NAME.dmg"

    mkdir -p "$DIST"
    rm -rf "$PACKAGE_APP" "$DMG_ROOT" "$PACKAGE_DMG"

    ditto "$APP" "$PACKAGE_APP"

    mkdir -p "$DMG_ROOT"
    ditto "$APP" "$DMG_ROOT/{{app_name}}.app"
    ln -s /Applications "$DMG_ROOT/Applications"

    hdiutil create \
      -volname "{{app_name}}" \
      -srcfolder "$DMG_ROOT" \
      -ov \
      -format UDZO \
      "$PACKAGE_DMG"

    rm -rf "$DMG_ROOT"

    echo "Packaged app: $PACKAGE_APP"
    echo "Packaged dmg: $PACKAGE_DMG"

# Build Release package and open build/dist in Finder
package-open: package
    open {{dist_dir}}
