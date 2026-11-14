#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
phase="${1:-all}"
case "$phase" in
  lint|test|release|all) ;;
  *) printf 'Usage: %s [lint|test|release|all]\n' "$0" >&2; exit 2 ;;
esac

if [[ "$(uname -m)" != arm64 || "$(sw_vers -productVersion)" != 26.* ]]; then
  printf 'Validation requires macOS 26 on arm64.\n' >&2
  exit 1
fi
if [[ "$(xcodebuild -version)" != $'Xcode 26.6\nBuild version 17F113' ]]; then
  printf 'Select Xcode 26.6 (17F113) using DEVELOPER_DIR.\n' >&2
  exit 1
fi

output_dir="${CONFLINGO_CI_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/conflingo-ci.XXXXXX")}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
printf 'Validation output: %s\n' "$output_dir"
xcodebuild -version
sw_vers

# Never enable paid evaluations in this validation entry point.
export CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 CONFLINGO_GROUNDING_LIVE_AI=0
export CONFLINGO_RAG_LIVE=0 CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0
export CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0

run_lint() {
  local lint_bin="${SWIFTLINT_BIN:-swiftlint}"
  if [[ "$("$lint_bin" version)" != 0.65.1 ]]; then
    printf 'SwiftLint 0.65.1 is required; see scripts/install-swiftlint.sh.\n' >&2
    return 1
  fi
  "$lint_bin" lint --strict --no-cache 2>&1 | tee "$output_dir/lint.log"
}

run_tests() {
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$output_dir/build" \
    -resultBundlePath "$output_dir/tests.xcresult" \
    -skip-testing:ConfLingoTests/GeminiLiveEvaluationTests \
    -skip-testing:ConfLingoTests/RAGLiveEvaluationTests \
    -skip-testing:ConfLingoTests/SummaryLiveEvaluationTests \
    -skip-testing:ConfLingoTests/ResponseSizeLiveEvaluationTests \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$output_dir/test.log"
}

run_release() {
  xcodebuild build -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$output_dir/build" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "$output_dir/release.log"
  local binary="$output_dir/build/Build/Products/Release/ConfLingo.app/Contents/MacOS/ConfLingo"
  lipo "$binary" -verify_arch arm64 x86_64
  lipo -info "$binary" | tee "$output_dir/architectures.log"
}

case "$phase" in
  lint) run_lint ;;
  test) run_tests ;;
  release) run_release ;;
  all) run_lint; run_tests; run_release ;;
esac
