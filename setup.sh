#!/usr/bin/env bash
#
# One-step install: ./setup.sh (or ./setup.sh --help for the other options).
#
# This app's settings are in app.env. The install steps come from swift-app-kit
# (github.com/VedAtal/swift-app-kit), at the version pinned in Package.resolved.
#
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swift >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  echo "error: Swift isn't installed. Finish installing the Command Line Tools in the window that just opened, then run ./setup.sh again." >&2
  exit 1
fi

# Downloads swift-app-kit the first time. With `swift package edit`, it uses your local copy.
if ! output=$(swift package resolve 2>&1); then
  printf '%s\n' "$output" >&2
  echo "error: Couldn't download swift-app-kit. Check your internet connection and try again." >&2
  exit 1
fi
deps=$(swift package show-dependencies --format json 2>/dev/null)
kit=""
for i in {0..20}; do
  identity=$(plutil -extract "dependencies.$i.identity" raw -o - - <<<"$deps" 2>/dev/null) || break
  if [[ "$identity" == "swift-app-kit" ]]; then
    kit=$(plutil -extract "dependencies.$i.path" raw -o - - <<<"$deps")
    break
  fi
done
[[ -n "$kit" ]] || { echo "error: Package.swift doesn't depend on swift-app-kit." >&2; exit 1; }

APP_ROOT="$PWD" exec /bin/bash "$kit/scripts/setup.sh" "$@"
