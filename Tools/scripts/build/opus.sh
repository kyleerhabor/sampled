#!/bin/sh

#  opus.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/build.sh"
. "$(dirname "$0")/scripts/build/opus/core.sh"

build "$PREFIX_FAT"
