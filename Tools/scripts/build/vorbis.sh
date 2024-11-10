#!/bin/sh

#  vorbis.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  local arch="$1"

  echo "Building Vorbis for $arch"

  local prefix="$(prefixarch "$arch")"
  local PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
  pushd "$CWD/$VORBISDIR"
  ./autogen.sh
  
  # Remove the obsolete -force_cpusubtype_ALL option from being passed to ld
  sed -i '' 's/-force_cpusubtype_ALL//g' configure
  ./configure --prefix="$CWD/$prefix" \
    --host="$arch-apple-darwin" \
    --build="$(uname -m)-apple-darwin" \
    --disable-shared \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    CC=clang \
    CFLAGS="-arch $arch $EXTRA_CFLAGS"

  runmake
  popd
}
