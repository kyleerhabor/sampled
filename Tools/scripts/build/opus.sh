#!/bin/sh

#  opus.sh
#  Forward
#
#  Created by Kyle Erhabor on 11/8/24.
#

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  echo 'Building Opus'

  local PATH="$CWD/$PREFIX/bin:$PATH"
  pushd "$CWD/$OPUSDIR"
  ./autogen.sh
  ./configure --prefix="$CWD/$PREFIX" \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --disable-intrinsics --disable-shared \
    CC=clang \
    CFLAGS="$EXTRA_CFLAGS $(prefix -arch "$ARCHS")"

  runmake
  popd
}
