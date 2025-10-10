#!/bin/sh

#  setup.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/10/24.
#

set -e

ARCH="$(uname -m)"
export ARCHS="${ARCHS:-"$ARCH"}"

# These have to be outside scripts so Xcode calls them from the Tools directory (otherwise, $0 wouldn't align with imports).
. "$(dirname "$0")/download-deps.sh"
. "$(dirname "$0")/build-ogg.sh"
. "$(dirname "$0")/build-vorbis.sh"
. "$(dirname "$0")/build-opus.sh"
. "$(dirname "$0")/build-ffmpeg.sh"
