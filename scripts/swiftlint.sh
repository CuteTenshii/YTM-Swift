#!/bin/sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v swiftlint >/dev/null; then
  echo "error: SwiftLint is required. Install it with: brew install swiftlint"
  exit 1
fi

swiftlint lint --strict --no-cache --config "${SRCROOT}/.swiftlint.yml"
