#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

PROJECT="StartMenu4Mac.xcodeproj"
SCHEME="StartMenu4Mac"
MODE="${1:---fast}"
if [[ $# -gt 1 || ( "$MODE" != "--fast" && "$MODE" != "--full" ) ]]; then
  echo "usage: bash scripts/check.sh [--fast|--full]" >&2
  exit 64
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/startmenu4mac-check.XXXXXX")"
trap 'rm -rf -- "$temporary_directory"' EXIT
derived_data_directory="$ROOT/.build/DerivedData"
mkdir -p "$derived_data_directory"

fail() {
  echo "CHECK FAILED: $*" >&2
  exit 3
}

localization_check() {
  local -a files=()
  local file locale reference_keys current_keys duplicate_keys placeholder_map
  local base_keys base_placeholders references

  while IFS= read -r file; do
    [[ -f "$file" ]] && files+=("$file")
  done < <(find StartMenu4Mac -type f -name 'Localizable.strings' -print | LC_ALL=C sort)
  (( ${#files[@]} > 0 )) || fail "no Localizable.strings files found"

  for ((index = 0; index < ${#files[@]}; index++)); do
    file="${files[$index]}"
    locale="${file#StartMenu4Mac/}"
    locale="${locale%%.lproj/*}"
    plutil -lint "$file" >/dev/null || fail "invalid .strings syntax: $file"

    current_keys="$temporary_directory/keys-$index"
    duplicate_keys="$temporary_directory/duplicates-$index"
    placeholder_map="$temporary_directory/placeholders-$index"
    perl -ne 'print "$1\n" if /^\s*"((?:\\.|[^"])*)"\s*=/' "$file" | LC_ALL=C sort > "$current_keys"
    [[ -s "$current_keys" ]] || fail "no localization keys found: $file"
    uniq -d "$current_keys" > "$duplicate_keys"
    [[ ! -s "$duplicate_keys" ]] || fail "duplicate localization keys in $file: $(tr '\n' ' ' < "$duplicate_keys")"

    perl -ne '
      if (/^\s*"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)"\s*;/) {
        my ($key, $value) = ($1, $2);
        my @tokens = ($value =~ /(%(?:[0-9]+\$)?[-+#0 ]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?(?:hh|h|ll|l|L|z|j|t|q)?[diuoxXfFeEgGaAcCsSp@%])/g);
        @tokens = sort @tokens;
        print "$key\t", join(" ", @tokens), "\n";
      }
    ' "$file" | LC_ALL=C sort > "$placeholder_map"

    if [[ "$locale" == "en" ]]; then
      base_keys="$current_keys"
      base_placeholders="$placeholder_map"
    fi
  done

  [[ -n "${base_keys:-}" ]] || fail "English localization (en) is missing"
  for locale in ja zh-Hans zh-Hant ko de fr es; do
    [[ -f "StartMenu4Mac/$locale.lproj/Localizable.strings" ]] || fail "required localization is missing: $locale"
  done
  for ((index = 0; index < ${#files[@]}; index++)); do
    file="${files[$index]}"
    locale="${file#StartMenu4Mac/}"
    locale="${locale%%.lproj/*}"
    current_keys="$temporary_directory/keys-$index"
    placeholder_map="$temporary_directory/placeholders-$index"
    cmp -s "$base_keys" "$current_keys" || fail "localization key mismatch: $locale"
    cmp -s "$base_placeholders" "$placeholder_map" || fail "format placeholder mismatch: $locale"
  done

  references="$temporary_directory/references"
  find StartMenu4Mac -type f -name '*.swift' -exec perl -ne 'while (/\btext\("([^"]+)"/g) { print "$1\n" }' {} + \
    | LC_ALL=C sort -u > "$references"
  reference_keys="$temporary_directory/reference-keys"
  LC_ALL=C sort -u "$base_keys" > "$reference_keys"
  comm -23 "$references" "$reference_keys" > "$temporary_directory/missing-references"
  [[ ! -s "$temporary_directory/missing-references" ]] \
    || fail "source localization keys are missing: $(tr '\n' ' ' < "$temporary_directory/missing-references")"

  printf 'localization: ok (%s locales; keys and placeholders match)\n' "${#files[@]}"
}

build_setting() {
  local configuration="$1"
  local key="$2"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$configuration" \
    -derivedDataPath "$derived_data_directory" \
    -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
    | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" && !found { value = $2; found = 1 } END { if (found) print value }'
}

verify_build_identity() {
  local debug_marketing release_marketing debug_build release_build
  local debug_deployment release_deployment
  debug_marketing="$(build_setting Debug MARKETING_VERSION)"
  release_marketing="$(build_setting Release MARKETING_VERSION)"
  debug_build="$(build_setting Debug CURRENT_PROJECT_VERSION)"
  release_build="$(build_setting Release CURRENT_PROJECT_VERSION)"
  debug_deployment="$(build_setting Debug MACOSX_DEPLOYMENT_TARGET)"
  release_deployment="$(build_setting Release MACOSX_DEPLOYMENT_TARGET)"

  [[ -n "$debug_marketing" && "$debug_marketing" == "$release_marketing" ]] \
    || fail "Debug and Release MARKETING_VERSION values are missing or differ"
  [[ "$debug_build" =~ ^[1-9][0-9]*$ ]] \
    || fail "Debug CURRENT_PROJECT_VERSION must be a positive integer (got: $debug_build)"
  [[ "$debug_build" == "$release_build" ]] \
    || fail "Debug and Release CURRENT_PROJECT_VERSION values differ"
  [[ -n "$debug_deployment" && "$debug_deployment" == "$release_deployment" ]] \
    || fail "Debug and Release MACOSX_DEPLOYMENT_TARGET values are missing or differ"
  [[ "$debug_deployment" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
    || fail "invalid macOS deployment target: $debug_deployment"

  printf 'build settings: marketing %s; build %s; macOS %s\n' \
    "$debug_marketing" "$debug_build" "$debug_deployment"
}

verify_app_metadata() {
  local configuration="$1"
  local target_build_dir wrapper_name app plist marketing build deployment minimum_system_version expected_marketing expected_build
  target_build_dir="$(build_setting "$configuration" TARGET_BUILD_DIR)"
  wrapper_name="$(build_setting "$configuration" WRAPPER_NAME)"
  app="$target_build_dir/$wrapper_name"
  plist="$app/Contents/Info.plist"
  [[ -d "$app" && -f "$plist" ]] || fail "$configuration app bundle is missing: $app"
  marketing="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" \
    || fail "$configuration app Info.plist is missing LSMinimumSystemVersion"
  expected_marketing="$(build_setting "$configuration" MARKETING_VERSION)"
  expected_build="$(build_setting "$configuration" CURRENT_PROJECT_VERSION)"
  deployment="$(build_setting "$configuration" MACOSX_DEPLOYMENT_TARGET)"
  [[ "$marketing" == "$expected_marketing" && "$build" == "$expected_build" ]] \
    || fail "$configuration app version metadata does not match build settings"
  [[ "$minimum_system_version" == "$deployment" ]] \
    || fail "$configuration app minimum system version does not match MACOSX_DEPLOYMENT_TARGET"

  while IFS= read -r localization; do
    local locale resource
    locale="${localization#StartMenu4Mac/}"
    locale="${locale%%.lproj/*}"
    resource="$app/Contents/Resources/$locale.lproj/Localizable.strings"
    [[ -f "$resource" ]] || fail "$configuration app lacks localization: $resource"
    plutil -lint "$resource" >/dev/null || fail "invalid packaged localization: $resource"
  done < <(find StartMenu4Mac -type f -name 'Localizable.strings' -print | LC_ALL=C sort)

  printf '%s app: %s (%s / %s; macOS %s)\n' "$configuration" "$app" "$marketing" "$build" "$deployment"
}

echo "== StartMenu4Mac public checks ($MODE) =="
verify_build_identity
swift -module-cache-path "$derived_data_directory/SwiftModuleCache" \
  "$SCRIPT_DIR/check-app-icon-geometry.swift" "$ROOT/StartMenu4Mac/Assets.xcassets/AppIconLegacy.appiconset"
git -c safe.directory="$ROOT" -C "$ROOT" diff --check
git -c safe.directory="$ROOT" -C "$ROOT" diff --cached --check
ignored_tracked_files="$(git -c safe.directory="$ROOT" -C "$ROOT" ls-files -ci --exclude-standard)"
[[ -z "$ignored_tracked_files" ]] || fail "tracked ignored files found: $ignored_tracked_files"
localization_check

echo "== XCTest =="
if [[ -d "$ROOT/StartMenu4MacTests" ]]; then
  test_source_count="$(find "$ROOT/StartMenu4MacTests" -type f -name '*.swift' -print | wc -l | tr -d ' ')"
  [[ "$test_source_count" -gt 0 ]] || fail "test source directory exists but contains no XCTest sources"
  xcodebuild -quiet -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' test \
    -derivedDataPath "$derived_data_directory" CODE_SIGNING_ALLOWED=NO
else
  echo "XCTest: not included in this public export by policy (StartMenu4MacTests/ is private-only)"
  if [[ "$MODE" == "--fast" ]]; then
    echo "== Debug build (public export; XCTest sources are private-only) =="
    xcodebuild -quiet -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build \
      -derivedDataPath "$derived_data_directory" CODE_SIGNING_ALLOWED=NO
  fi
fi

if [[ "$MODE" == "--full" ]]; then
  echo "== Debug build =="
  xcodebuild -quiet -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build \
    -derivedDataPath "$derived_data_directory" CODE_SIGNING_ALLOWED=NO
  echo "== Release build =="
  xcodebuild -quiet -project "$PROJECT" -scheme "$SCHEME" -configuration Release build \
    -derivedDataPath "$derived_data_directory" CODE_SIGNING_ALLOWED=NO

  [[ "$(build_setting Debug SWIFT_OPTIMIZATION_LEVEL)" == "-Onone" ]] || fail "Debug optimization is not -Onone"
  [[ "$(build_setting Release SWIFT_OPTIMIZATION_LEVEL)" != "-Onone" ]] || fail "Release is using Debug optimization"
  [[ "$(build_setting Release ENABLE_HARDENED_RUNTIME)" == "YES" ]] || fail "Release Hardened Runtime is not enabled"
  [[ "$(build_setting Debug ENABLE_APP_SANDBOX)" == "NO" && "$(build_setting Release ENABLE_APP_SANDBOX)" == "NO" ]] \
    || fail "unexpected app sandbox setting"
  [[ -z "$(build_setting Debug CODE_SIGN_ENTITLEMENTS)" && -z "$(build_setting Release CODE_SIGN_ENTITLEMENTS)" ]] \
    || fail "unexpected code-signing entitlements"
  verify_app_metadata Debug
  verify_app_metadata Release

  if [[ -x scripts/export-public.sh || -f scripts/export-public.sh ]]; then
    echo "== Public export smoke test (committed source) =="
    public_export_directory="$(mktemp -d "${TMPDIR:-/tmp}/startmenu4mac-export.XXXXXX")"
    trap 'rm -rf -- "$temporary_directory" "$public_export_directory"' EXIT
    bash scripts/export-public.sh "$public_export_directory"
  else
    echo "public export smoke: skipped (the exporter is private-only and is not present in this checkout)"
  fi
  echo "full checks: ok"
fi
