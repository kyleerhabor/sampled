#!/bin/sh

#  xcode.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

. "$(dirname "$0")/scripts/build.sh"

#for arch in $ARCHS; do
#  prefix="$(prefixarch "$arch")"
#
#  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
#done
#
#echo "$PKG_CONFIG_PATH"

if [ "$CONFIGURATION" != "Debug" ]; then
  export EXTRA_CFLAGS="-O3"
fi
