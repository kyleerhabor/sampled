#!/bin/sh

#  ffmpeg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

set -e

. "$(dirname "$0")/scripts/build/ffmpeg/core.sh"

for arch in $ARCHS; do
  build "$arch" "$(prefixarch "$arch")"
done
