#!/bin/sh

#  build-opus.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/9/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  local arch="$1"
  echo "Building libopus for $arch"

  local PATH="$CWD/$(prefix "$arch")/bin:$PATH"
  pushd "$CWD/$OPUSDIR"
  ./autogen.sh

  # We can configure libopus to build for multiple architectures, but it requires manual code signing to launch the app.
  #
  # TODO: Add note about host-build confusion.
  ./configure --prefix="$CWD/$(prefix "$arch")" \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --disable-intrinsics --disable-shared \
    --build="$(uname -m)-apple-darwin" \
    --host="$arch-apple-darwin" \
    CC=clang \
    CFLAGS="-arch $arch $EXTRA_CFLAGS" \

  runmake
  popd
}

for arch in $ARCHS; do
  build "$arch"
done
