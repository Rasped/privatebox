#!/usr/bin/env bash
set -euo pipefail

# Debug test for FreeBSD auto-installer ISO build
# This temporarily uses build-debug.sh to get more info

echo "=== FreeBSD ISO Debug Test ==="

# Create a modified version of the build script that uses debug
cp bootstrap/build_freebsd_autoiso.sh bootstrap/build_freebsd_autoiso_debug.sh

# Replace build.sh with build-debug.sh in the debug version
sed -i.bak 's|bootstrap/iso/build.sh|bootstrap/iso/build-debug.sh|' bootstrap/build_freebsd_autoiso_debug.sh

# Run the debug version
bash bootstrap/build_freebsd_autoiso_debug.sh

echo "Debug build complete"