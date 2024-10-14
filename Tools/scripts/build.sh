#!/bin/sh

#  build.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/core.sh"

CFFMPEGDIR=ForwardFFmpeg/Sources/CFFmpeg
DEPSDIR=deps
export OPUSDIR="$DEPSDIR/opus"
export FFMPEGDIR="$DEPSDIR/ffmpeg"

prefix () {
  local arch="$1"

  echo "$CFFMPEGDIR/$arch"
}

NCPU="$(sysctl -n hw.ncpu)"
NJOB="$(max 1 "$(($NCPU / 2))")"

runmake () {
  make -j"$NJOB"
  make install
  make distclean
}
