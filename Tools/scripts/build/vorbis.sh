#!/bin/sh

#  vorbis.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  echo 'Building Vorbis'

  local PATH="$CWD/$PREFIX/bin:$PATH"
  pushd "$CWD/$VORBISDIR"
  ./autogen.sh

  # Remove the obsolete -force_cpusubtype_ALL option from being passed to ld
  sed -i '' 's/-force_cpusubtype_ALL//g' configure
  ./configure --prefix="$CWD/$PREFIX" \
    --disable-shared \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    CC=clang \
    CFLAGS="$EXTRA_CFLAGS $(prefix -arch "$ARCHS")"

  runmake
  popd
}
