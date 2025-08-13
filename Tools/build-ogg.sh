#!/bin/sh

#  build-ogg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/9/24.
#  

set -e

. "$(dirname "$0")/scripts/build/ogg.sh"
. "$(dirname "$0")/scripts/xcode.sh"

for arch in $ARCHS; do
  build "$arch"
done
