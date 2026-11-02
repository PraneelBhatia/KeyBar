#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
args=()
developer_dir="$(xcode-select -p)"
# Command Line Tools ship Swift Testing outside the default framework search path.
frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ "$developer_dir" == */CommandLineTools && -d "$frameworks/Testing.framework" ]]; then
    # CLT 6.2 omits the Foundation testing overlay's module interface.
    args+=(-Xswiftc -F -Xswiftc "$frameworks" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
           -Xlinker -rpath -Xlinker "$frameworks")
fi
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
    --cache-path .build/cache --config-path .build/config --security-path .build/security "${args[@]}"
