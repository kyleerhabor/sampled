#!/bin/sh

#  build-vorbis.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

set -e

. "$(dirname "$0")/scripts/build/vorbis.sh"
. "$(dirname "$0")/scripts/xcode.sh"

for arch in $ARCHS; do
  build "$arch"
done
