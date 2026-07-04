#!/bin/sh

#  user.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

export BUILD_ARCHS="${ARCHS:-$(uname -m)}"
export BUILD_DRY_RUN="${DRY_RUN:-}"
export BUILD_VERBOSE="${VERBOSE:-}"
. ./Tools/core/build.sh
. ./Tools/core/install.sh
