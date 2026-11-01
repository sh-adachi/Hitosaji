#!/bin/bash
set -euo pipefail

hitosaji_root="$(cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
hitosaji_test_dir="$hitosaji_root/.build/core"
/bin/mkdir -p "$hitosaji_test_dir/ModuleCache" "$hitosaji_test_dir/cache"

export CLANG_MODULE_CACHE_PATH="$hitosaji_test_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$hitosaji_test_dir/ModuleCache"

cd "$hitosaji_root"
exec /usr/bin/swift test \
  --disable-sandbox \
  --scratch-path "$hitosaji_test_dir/build" \
  --cache-path "$hitosaji_test_dir/cache" \
  -Xswiftc -module-cache-path \
  -Xswiftc "$hitosaji_test_dir/ModuleCache" \
  "$@"
