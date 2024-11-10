#!/bin/sh

#  build.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/core.sh"

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
  make clean
}
