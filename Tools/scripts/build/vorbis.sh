#!/bin/sh

#  vorbis.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

set -e

. "$(dirname "$0")/scripts/build/vorbis/core.sh"

build "$PREFIX_FAT"
