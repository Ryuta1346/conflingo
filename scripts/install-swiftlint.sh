#!/usr/bin/env bash
set -euo pipefail

tool_dir="${1:?Usage: install-swiftlint.sh INSTALL_DIRECTORY}"
mkdir -p "$tool_dir"
archive="$tool_dir/portable_swiftlint.zip"
curl --fail --location --retry 3 \
  https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip \
  --output "$archive"
printf '%s  %s\n' 'c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0' "$archive" | shasum -a 256 -c -
unzip -oq "$archive" -d "$tool_dir"
chmod +x "$tool_dir/swiftlint"
[[ "$("$tool_dir/swiftlint" version)" == 0.65.1 ]]
