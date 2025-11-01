#!/bin/sh

#  xcode.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

# We're using sh, so we don't have whatever Zsh or Bash sources.
export PATH="$(env brew --prefix)/bin:$PATH"

if [ "$CONFIGURATION" = "Release" ]; then
  export EXTRA_CFLAGS="-O3"
  export EXTRA_FFMPEGFLAGS=(--disable-programs --disable-doc)
fi
