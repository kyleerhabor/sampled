#!/bin/sh

#  vorbis.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

# TODO: Silence warnings
build () {
  local arch="$1"
  echo "Building Vorbis for $arch"

  local prefix="$(prefixarch "$arch")"
  pushd "$CWD/$VORBISDIR"
  ./autogen.sh

  # Remove obsolete -force_cpusubtype_ALL option so it's not passed to ld
  #
  # https://github.com/Homebrew/homebrew-core/blob/35ebe9ef7f7f78c7e5ca425b6c90415c608788ab/Formula/lib/libvorbis.rb#L49
  sed -i '' 's/-force_cpusubtype_ALL//g' configure

  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH" \
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
