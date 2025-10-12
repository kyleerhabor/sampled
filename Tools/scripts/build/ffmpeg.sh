#!/bin/sh

#  ffmpeg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/build.sh"
. "$(dirname "$0")/scripts/build/ffmpeg/core.sh"

for arch in $ARCHS; do
  build "$(prefixarch "$arch")" "$arch"
done
