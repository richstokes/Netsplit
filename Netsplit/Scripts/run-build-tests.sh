#!/bin/sh

set -eu

# The shared Run/Build workflow is Debug. Release archives intentionally do
# not embed a test bundle, and the Test action remains independently available.
if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
    exit 0
fi

test_bundle="$BUILT_PRODUCTS_DIR/Netsplit.app/Contents/PlugIns/NetsplitTests.xctest"
if [ ! -d "$test_bundle" ]; then
    echo "error: NetsplitTests.xctest was not built by the shared scheme." >&2
    exit 1
fi

echo "Running fast Netsplit regression tests…"
unset SWIFT_DEBUG_INFORMATION_FORMAT SWIFT_DEBUG_INFORMATION_VERSION
/usr/bin/xcrun xctest "$test_bundle"
