#!/bin/sh

#  setup.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/10/24.
#

set -e

ARCH="$(uname -m)"
export ARCHS="${ARCHS:-"$ARCH"}"

. "$(dirname "$0")/download-deps.sh"
. "$(dirname "$0")/scripts/build/ogg.sh"
. "$(dirname "$0")/scripts/build/vorbis.sh"
. "$(dirname "$0")/scripts/build/opus.sh"
. "$(dirname "$0")/scripts/build/ffmpeg.sh"
