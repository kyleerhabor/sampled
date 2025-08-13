#!/bin/sh

#  build.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/core.sh"

# Xcode is preparing the editor by pre-building the project. A formal build takes a while and risks errors from
# concurrently executing scripts, so we disallow this. A better solution would be to introduce locks.
if [ "$ACTION" = indexbuild ]; then
  exit 0
fi

PREFIX=SampledFFmpeg/Sources/CFFmpeg
DEPSDIR=deps
export OGGDIR="$DEPSDIR/ogg"
export VORBISDIR="$DEPSDIR/vorbis"
export OPUSDIR="$DEPSDIR/opus"
export FFMPEGDIR="$DEPSDIR/ffmpeg"

prefixarch () {
  local arch="$1"
  
  echo "$PREFIX/$arch"
}

NCPU="$(sysctl -n hw.ncpu)"
NJOB="$(max 1 "$(($NCPU / 2))")"

runmake () {
  make -j"$NJOB"
  make install
  # make clean
}
