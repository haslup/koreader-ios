#!/usr/bin/env bash
# Build KOReader for iOS, sign it, install it on a device and launch it.
#
# Usage: platform/ios/deploy.sh [options]
#   --regen         regenerate KOReader.xcodeproj first (make TARGET=ios xcodeproj);
#                   done automatically when the project is missing or older
#                   than platform/ios/project.yml or local.config
#   --device X      device name or UDID (default: IOS_DEVICE in local.config,
#                   else the only connected physical iPhone/iPad)
#   --release       build the Release configuration (default: Debug)
#   --no-install    build only
#   --no-launch     install, but don't launch
#   --console       launch attached and stream KOReader's log here
#                   (Ctrl-C detaches, which also quits the app)
#
# Signing settings come from platform/ios/local.config (git-ignored); copy
# platform/ios/local.config.example and fill in IOS_TEAM_ID and IOS_BUNDLE_ID.
# Xcode must be signed in to that team's Apple account (Xcode > Settings >
# Apple Accounts); provisioning profiles are created and renewed automatically.
# The device needs Developer Mode on, and must be unlocked to launch the app.

set -euo pipefail

die() { echo "deploy: $*" >&2; exit 1; }
say() { echo "==> $*"; }

cd "$(dirname "$0")/../.."
ROOT=$PWD

regen=0 install=1 launch=1 console=0 configuration=Debug device_arg=""
while [ $# -gt 0 ]; do
    case "$1" in
        --regen) regen=1 ;;
        --device) shift; [ $# -gt 0 ] || die "--device needs a name or UDID"; device_arg=$1 ;;
        --release) configuration=Release ;;
        --no-install) install=0; launch=0 ;;
        --no-launch) launch=0 ;;
        --console) console=1 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

# GNU tools first on PATH, for this script only (same as the Xcode build
# phase in project.yml).
command -v brew >/dev/null || die "Homebrew is required (https://brew.sh)"
BREW_PREFIX="$(brew --prefix)"
export PATH="${BREW_PREFIX}/opt/findutils/libexec/gnubin:${BREW_PREFIX}/opt/gnu-getopt/bin:${BREW_PREFIX}/opt/make/libexec/gnubin:${BREW_PREFIX}/opt/util-linux/bin:${PATH}"

# --- configuration -----------------------------------------------------------

CONFIG=platform/ios/local.config
config() {  # config KEY -> value from local.config ("KEY = value" or "KEY=value")
    [ -f "$CONFIG" ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*[?:]*=[[:space:]]*//p" "$CONFIG" | tail -n 1 | sed 's/[[:space:]]*$//'
}
TEAM=${IOS_TEAM_ID:-$(config IOS_TEAM_ID)}
BUNDLE=${IOS_BUNDLE_ID:-$(config IOS_BUNDLE_ID)}
DEVICE=${device_arg:-${IOS_DEVICE:-$(config IOS_DEVICE)}}
[ -n "$TEAM" ] || die "IOS_TEAM_ID is not set; copy platform/ios/local.config.example to $CONFIG and fill it in"
[ -n "$BUNDLE" ] || die "IOS_BUNDLE_ID is not set in $CONFIG"

# --- device ------------------------------------------------------------------

UDID="" DEVICE_NAME=""
if [ "$install" = 1 ]; then
    devices_json=$(mktemp -t koreader-devices)
    trap 'rm -f "$devices_json"' EXIT
    xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 \
        || die "xcrun devicectl failed; is Xcode installed and selected (xcode-select -p)?"
    # Prints "UDID<TAB>name" for the chosen device, or an error on stderr.
    pick=$(python3 -I - "$devices_json" "$DEVICE" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
devs = []
for d in json.load(open(path))["result"]["devices"]:
    h, p, c = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    if h.get("platform") != "iOS" or h.get("reality") != "physical":
        continue
    devs.append((h.get("udid"), p.get("name"), c.get("tunnelState"), p.get("developerModeStatus")))
if want:
    match = [d for d in devs if want in (d[0], d[1])]
else:
    match = [d for d in devs if d[2] == "connected"]
if len(match) != 1:
    what = f"named '{want}'" if want else "connected"
    sys.stderr.write(f"deploy: found {len(match)} physical iPhone/iPad devices {what}; use --device or IOS_DEVICE.\n")
    for d in devs:
        sys.stderr.write(f"  {d[1]}  {d[0]}  ({d[2]}, developer mode {d[3]})\n")
    sys.exit(1)
udid, name, _, devmode = match[0]
if devmode not in (None, "enabled"):
    sys.stderr.write(f"deploy: Developer Mode is '{devmode}' on {name}; turn it on in Settings > Privacy & Security.\n")
    sys.exit(1)
print(f"{udid}\t{name}")
PY
    ) || exit 1
    UDID=${pick%%$'\t'*}
    DEVICE_NAME=${pick#*$'\t'}
    say "Device: $DEVICE_NAME ($UDID)"
fi

# --- build -------------------------------------------------------------------

mkdir -p build-logs
PROJECT=KOReader.xcodeproj
if [ "$regen" = 0 ]; then
    if [ ! -f "$PROJECT/project.pbxproj" ] \
        || [ platform/ios/project.yml -nt "$PROJECT/project.pbxproj" ] \
        || { [ -f "$CONFIG" ] && [ "$CONFIG" -nt "$PROJECT/project.pbxproj" ]; }; then
        regen=1
    fi
fi
if [ "$regen" = 1 ]; then
    say "Generating $PROJECT (make TARGET=ios xcodeproj; log: build-logs/deploy-make.log)"
    make TARGET=ios xcodeproj > build-logs/deploy-make.log 2>&1 \
        || { tail -n 30 build-logs/deploy-make.log; die "make TARGET=ios xcodeproj failed"; }
else
    # Refreshes the staging tree, git-rev (the version KOReader shows) and
    # Info.plist's version, which Xcode's own build phase doesn't reliably do.
    say "Updating the staging tree and version (log: build-logs/deploy-make.log)"
    make TARGET=ios all ios-info-plist > build-logs/deploy-make.log 2>&1 \
        || { tail -n 30 build-logs/deploy-make.log; die "make TARGET=ios all failed"; }
fi
say "Version: $(cat koreader-ios-*/koreader/git-rev 2>/dev/null || echo unknown)"

if [ -n "$UDID" ]; then destination="id=$UDID"; else destination="generic/platform=iOS"; fi
xcode_args=(
    -project "$PROJECT" -scheme KOReader -configuration "$configuration"
    -destination "$destination" -allowProvisioningUpdates
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" CODE_SIGN_STYLE=Automatic
)
say "Building $configuration, signed for team $TEAM (log: build-logs/deploy-xcodebuild.log)"
xcodebuild "${xcode_args[@]}" build > build-logs/deploy-xcodebuild.log 2>&1 \
    || { grep -E "error:|BUILD FAILED" build-logs/deploy-xcodebuild.log | tail -n 20; die "xcodebuild failed"; }

APP=$(xcodebuild "${xcode_args[@]}" -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *CODESIGNING_FOLDER_PATH = //p' | head -n 1)
[ -d "$APP" ] || die "built app not found (CODESIGNING_FOLDER_PATH='$APP')"
say "Built $APP ($(cat "$APP/app/git-rev" 2>/dev/null || echo 'no git-rev'))"

[ "$install" = 1 ] || exit 0

# --- install and launch --------------------------------------------------------

say "Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$UDID" "$APP" > build-logs/deploy-install.log 2>&1 \
    || { tail -n 20 build-logs/deploy-install.log; die "install failed"; }

[ "$launch" = 1 ] || { say "Installed (not launched)."; exit 0; }

launch_args=(device process launch --terminate-existing --device "$UDID")
if [ "$console" = 1 ]; then
    say "Launching $BUNDLE with its log attached (Ctrl-C detaches and quits the app)"
    exec xcrun devicectl "${launch_args[@]}" --console "$BUNDLE"
fi
say "Launching $BUNDLE"
xcrun devicectl "${launch_args[@]}" "$BUNDLE" > build-logs/deploy-launch.log 2>&1 \
    || { tail -n 20 build-logs/deploy-launch.log; die "launch failed (is the device unlocked?)"; }
say "Done."
