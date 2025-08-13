#!/bin/sh

#  setup.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/10/24.
#

set -e

export ARCHS="$(uname -m)"
# TODO: Abstract away Xcode
export CONFIGURATION=Debug

. "$(dirname "$0")/download-deps.sh"
. "$(dirname "$0")/build-ogg.sh"
. "$(dirname "$0")/build-vorbis.sh"
. "$(dirname "$0")/build-opus.sh"
. "$(dirname "$0")/build-ffmpeg.sh"
