#!/bin/sh

#  user.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

export ARCHS="${ARCHS:-$(uname -m)}"
. ./Tools/core/build.sh
