#!/bin/sh

#  ogg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/9/24.
#  

. "$(dirname "$0")/scripts/build.sh"
. "$(dirname "$0")/scripts/build/ogg/core.sh"

build "$PREFIX_FAT"
