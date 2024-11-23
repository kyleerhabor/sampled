#!/bin/sh

#  opus.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  local arch="$1"

  echo "Building Opus for $arch"

  local prefix="$(prefixarch "$arch")"
  pushd "$CWD/$OPUSDIR"
  ./autogen.sh

  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH" \
  ./configure --prefix="$CWD/$prefix" \
    --host="$arch-apple-darwin" \
    --build="$(uname -m)-apple-darwin" \
    --disable-intrinsics --disable-shared \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    CC=clang \
    CFLAGS="-arch $arch $EXTRA_CFLAGS"

  runmake
  popd
}
