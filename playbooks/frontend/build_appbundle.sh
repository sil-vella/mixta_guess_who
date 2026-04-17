#!/bin/bash

# Flutter App Bundle (AAB) build script
# Builds an Android App Bundle for Dutch with the same dart-define/env flow
# as build_apk.sh (local or vps backend).
# Output is for Play Store upload; no VPS upload.

set -e

echo "🚀 Building Flutter App Bundle (AAB) for Dutch..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.prod"

# Determine backend target from first argument: 'local' or 'vps' (default: vps for distribution)
BACKEND_TARGET="${1:-vps}"

if [ "$BACKEND_TARGET" = "local" ]; then
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="https://guesswho.mixta.mt"
    WS_URL="wss://guesswho.mixta.mt/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Load env from repo root .env.prod (APP_VERSION, Firebase, GOOGLE_CLIENT_ID, Stripe, AdMob, AdSense, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — dart-defines (Firebase, Google Sign-In, etc.) will be empty."
fi
# APP_VERSION SSOT: .env.prod; interactive patch bump shared with build_apk.sh
# shellcheck source=/dev/null
source "$SCRIPT_DIR/bump_app_version_prompt.sh"
bump_app_version_prompt

# Derive a numeric build number from APP_VERSION (e.g. 2.1.0 -> 20100)
IFS='.' read -r APP_MAJOR APP_MINOR APP_PATCH <<< "$APP_VERSION"
APP_MAJOR=${APP_MAJOR:-0}
APP_MINOR=${APP_MINOR:-0}
APP_PATCH=${APP_PATCH:-0}
if ! [[ "$APP_MAJOR" =~ ^[0-9]+$ ]]; then APP_MAJOR=0; fi
if ! [[ "$APP_MINOR" =~ ^[0-9]+$ ]]; then APP_MINOR=0; fi
if ! [[ "$APP_PATCH" =~ ^[0-9]+$ ]]; then APP_PATCH=0; fi
BUILD_NUMBER=$((APP_MAJOR * 10000 + APP_MINOR * 100 + APP_PATCH))
echo "🔢 Using BUILD_NUMBER=$BUILD_NUMBER"

# Navigate to Flutter project directory
cd "$REPO_ROOT/mixta_flutter"

# Disable LOGGING_SWITCH in all Dart files before build
echo ""
echo "🔇 Disabling LOGGING_SWITCH in Flutter sources..."
FLUTTER_DIR="$REPO_ROOT/mixta_flutter"
REPLACED_FILES=0
REPLACED_OCCURRENCES=0

# Predefined variable value to avoid accidentally replacing other 'true' values
logging_switch_variable_value="true"

while IFS= read -r -d '' dart_file; do
    # Check if file contains LOGGING_SWITCH = false pattern
    if grep -q "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "static const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null; then
        # Count occurrences before replacement
        OCCURRENCES=$(grep -o "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')
        OCCURRENCES=$((OCCURRENCES + $(grep -o "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')))
        OCCURRENCES=$((OCCURRENCES + $(grep -o "static const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')))

        # Use sed for in-place replacement (works on both macOS and Linux)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
            sed -i '' "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
            sed -i '' "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
        else
            sed -i "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
            sed -i "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
            sed -i "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
        fi

        REPLACED_OCCURRENCES=$((REPLACED_OCCURRENCES + OCCURRENCES))
        REPLACED_FILES=$((REPLACED_FILES + 1))
        REL_PATH="${dart_file#$FLUTTER_DIR/}"
        echo "  ✓ Updated $REL_PATH ($OCCURRENCES occurrence(s))"
    fi
done < <(find "$FLUTTER_DIR" -name "*.dart" -type f -print0)

if [ "$REPLACED_FILES" -eq 0 ]; then
    echo "  ℹ️  No LOGGING_SWITCH = ${logging_switch_variable_value} found in Flutter sources (already disabled or not present)."
else
    echo "  ✅ Disabled LOGGING_SWITCH in $REPLACED_OCCURRENCES place(s) across $REPLACED_FILES file(s)"
fi
echo ""

# Build --dart-define from .env.prod (all vars) then overrides and build-only extras (same as build_apk.sh)
source "$SCRIPT_DIR/dart_defines_from_env.sh"
DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=( "$line" )
done < <(build_dart_defines_from_env "$FRONTEND_ENV")
# Overrides (script-set API_URL, WS_URL, APP_VERSION)
DART_DEFINE_ARGS+=( --dart-define=API_URL="$API_URL" --dart-define=WS_URL="$WS_URL" --dart-define=APP_VERSION="$APP_VERSION" )
# Ensure Firebase runtime toggle is always present (defaults to true when missing).
DART_DEFINE_ARGS+=( --dart-define=FIREBASE_SWITCH="${FIREBASE_SWITCH:-true}" )
# Build-only (not in .env)
DART_DEFINE_ARGS+=( \
  --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
  --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
  --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
  --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
  --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
  --dart-define=DEBUG_MODE=true \
  --dart-define=ENABLE_REMOTE_LOGGING=true \
)

# Build the release App Bundle (AAB) for Play Store
flutter build appbundle \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  "${DART_DEFINE_ARGS[@]}"

OUTPUT_AAB="$REPO_ROOT/mixta_flutter/build/app/outputs/bundle/release/app-release.aab"

if [ -f "$OUTPUT_AAB" ]; then
  echo "✅ App Bundle build completed: $OUTPUT_AAB"
  ls -lh "$OUTPUT_AAB"
  echo ""
  echo "📤 Upload to Play Console: Release → Create new release → Upload this AAB"
else
  echo "❌ App Bundle build finished but $OUTPUT_AAB was not found. Check Flutter build output above."
  exit 1
fi
