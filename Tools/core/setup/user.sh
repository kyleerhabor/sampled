#!/bin/sh

#  user.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

export BUILD_ARCHS="${ARCHS:-$(uname -m)}"
export BUILD_DRY_RUN="${DRY_RUN:-}"
. ./Tools/core/build.sh
