#!/bin/sh

#  build-ffmpeg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/build/ffmpeg.sh"
. "$(dirname "$0")/scripts/xcode.sh"

for arch in $ARCHS; do
  build "$arch"
done
