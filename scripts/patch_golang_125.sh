#!/usr/bin/env bash

set -Eeuo pipefail

root_dir="$(git rev-parse --show-toplevel)"
build_dir="${BUILD_DIR:-$root_dir/.build}"
sdk_dir="$build_dir/sdk"

GO_VERSION="${GO_VERSION:-1.25.3}"

GO_TARBALL="go${GO_VERSION}.src.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

GO_SOURCE_DIR="$build_dir/go-${GO_VERSION}-src"

echo
echo "========================================"
echo "OpenWrt Go toolchain replacement"
echo "========================================"

echo "SDK:"
echo "$sdk_dir"

echo "Required Go:"
echo "$GO_VERSION"

# ============================================================
# Check SDK
# ============================================================

if [ ! -d "$sdk_dir" ]; then
    echo "ERROR: OpenWrt SDK does not exist:"
    echo "$sdk_dir"
    exit 1
fi

# ============================================================
# Download Go source
# ============================================================

archive="$build_dir/$GO_TARBALL"

if [ ! -f "$archive" ]; then

    echo
    echo "Downloading Go ${GO_VERSION} source..."

    curl \
        --fail \
        --location \
        --retry 4 \
        --retry-delay 2 \
        "$GO_URL" \
        -o "$archive"
fi

# ============================================================
# Extract
# ============================================================

rm -rf "$GO_SOURCE_DIR"

mkdir -p "$GO_SOURCE_DIR"

tar \
    -xzf "$archive" \
    --strip-components=1 \
    -C "$GO_SOURCE_DIR"

echo
echo "Go source extracted:"
echo "$GO_SOURCE_DIR"

# ============================================================
# Locate OpenWrt golang package
# ============================================================

GOLANG_DIR=""

if [ -d "$sdk_dir/feeds/packages/lang/golang" ]; then
    GOLANG_DIR="$sdk_dir/feeds/packages/lang/golang"
elif [ -d "$sdk_dir/package/feeds/packages/golang" ]; then
    GOLANG_DIR="$sdk_dir/package/feeds/packages/golang"
elif [ -d "$sdk_dir/package/golang" ]; then
    GOLANG_DIR="$sdk_dir/package/golang"
fi

if [ -z "$GOLANG_DIR" ]; then

    echo
    echo "ERROR: OpenWrt golang package was not found."

    echo
    echo "Searching SDK..."

    find "$sdk_dir" \
        -type f \
        -name 'golang-package.mk' \
        -o -name 'golang/Makefile' \
        2>/dev/null \
        | head -50

    exit 1
fi

echo
echo "OpenWrt Go package:"
echo "$GOLANG_DIR"

# ============================================================
# Show current Go version
# ============================================================

echo
echo "Current SDK Go:"

if [ -x "$sdk_dir/staging_dir/host/bin/go" ]; then
    "$sdk_dir/staging_dir/host/bin/go" version || true
fi

# ============================================================
# Find Go version definitions
# ============================================================

echo
echo "Searching Go version definitions..."

grep -R \
    -n \
    -E \
    'GOLANG_VERSION|PKG_VERSION.*go1|go1\.[0-9]' \
    "$GOLANG_DIR" \
    2>/dev/null \
    | head -100 \
    || true

# ============================================================
# Important:
#
# Do NOT modify the OpenWrt package infrastructure blindly.
#
# Instead, locate the version variable used by the SDK.
# ============================================================

golang_makefile="$GOLANG_DIR/Makefile"

if [ ! -f "$golang_makefile" ]; then

    echo
    echo "ERROR: Go Makefile not found:"
    echo "$golang_makefile"

    exit 1
fi

echo
echo "Go Makefile:"
echo "$golang_makefile"

# ============================================================
# Backup
# ============================================================

cp -a \
    "$golang_makefile" \
    "$golang_makefile.before-go125"

# ============================================================
# Patch version
# ============================================================

echo
echo "Attempting to update Go version..."

python3 - "$golang_makefile" "$GO_VERSION" <<'PY'
import sys
import re

path = sys.argv[1]
version = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = f.read()

patterns = [
    r'^(GOLANG_VERSION\s*:?=\s*)[0-9.]+',
    r'^(PKG_VERSION\s*:?=\s*)[0-9.]+',
]

changed = False

lines = data.splitlines(True)

for i, line in enumerate(lines):

    for pattern in patterns:

        new_line, count = re.subn(
            pattern,
            rf'\g<1>{version}',
            line,
            flags=re.MULTILINE
        )

        if count:
            lines[i] = new_line
            changed = True
            break

if not changed:
    print("ERROR: Could not find Go version variable.")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write("".join(lines))

print(f"Updated Go version to {version}")
PY

# ============================================================
# Show result
# ============================================================

echo
echo "========================================"
echo "Patched Go Makefile"
echo "========================================"

grep -n \
    -E \
    'GOLANG_VERSION|PKG_VERSION' \
    "$golang_makefile" \
    | head -20 \
    || true

# ============================================================
# Clean previous Go build
# ============================================================

echo
echo "Cleaning old Go build..."

rm -rf \
    "$sdk_dir/build_dir/host/golang"* \
    "$sdk_dir/build_dir/hostpkg/golang"* \
    "$sdk_dir/staging_dir/host/golang"* \
    "$sdk_dir/staging_dir/hostpkg/golang"*

# ============================================================
# Reconfigure
# ============================================================

echo
echo "========================================"
echo "Reconfiguring OpenWrt SDK"
echo "========================================"

pushd "$sdk_dir" >/dev/null

make defconfig

echo
echo "========================================"
echo "Building OpenWrt host Go"
echo "========================================"

make package/feeds/packages/golang/host/compile V=s \
    || make package/golang/host/compile V=s

popd >/dev/null

# ============================================================
# Verify
# ============================================================

echo
echo "========================================"
echo "Verifying SDK Go"
echo "========================================"

if [ ! -x "$sdk_dir/staging_dir/host/bin/go" ]; then

    echo "ERROR: SDK Go binary was not generated."

    find "$sdk_dir/staging_dir" \
        -type f \
        -name go \
        -perm -111 \
        2>/dev/null \
        | head -50

    exit 1
fi

"$sdk_dir/staging_dir/host/bin/go" version

echo
echo "========================================"
echo "Go toolchain patch completed"
echo "========================================"
