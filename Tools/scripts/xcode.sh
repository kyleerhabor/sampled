#!/bin/sh

#  xcode.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

if [ "$CONFIGURATION" = "Release" ]; then
  export EXTRA_CFLAGS="-O3"
  export EXTRA_FFMPEGFLAGS=(--disable-programs --disable-doc)
fi
