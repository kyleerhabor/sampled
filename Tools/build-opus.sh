#!/bin/sh

#  build-opus.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

set -e

. "$(dirname "$0")/scripts/build/opus.sh"
. "$(dirname "$0")/scripts/xcode.sh"

for arch in $ARCHS; do
  build "$arch"
done
