#!/bin/sh

#  core.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

# TODO: Silence warnings
build () {
  local prefix="$1"
  echo "Building Opus for $ARCHS"

  local arch_flags="$(prefix "-arch" "$ARCHS")"
  pushd "$CWD/$OPUSDIR"
  ./autogen.sh

  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH" \
  ./configure --prefix="$CWD/$prefix" \
    --host="$(uname -m)-apple-darwin" \
    --disable-intrinsics --disable-shared \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    CC=clang \
    CFLAGS="$arch_flags $EXTRA_CFLAGS"

  runmake
  popd
}
