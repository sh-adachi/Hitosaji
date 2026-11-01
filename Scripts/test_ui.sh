#!/bin/bash
set -euo pipefail

hitosaji_root="$(cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$hitosaji_root"
mkdir -p Artifacts
hitosaji_stamp="$(date +%Y%m%d-%H%M%S)"
exec /usr/bin/xcodebuild \
  -project Hitosaji.xcodeproj -scheme Hitosaji \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/DerivedData \
  -parallel-testing-enabled NO \
  -resultBundlePath "Artifacts/UITests-$hitosaji_stamp.xcresult" \
  CODE_SIGNING_ALLOWED=NO test "$@"
