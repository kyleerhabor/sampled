#!/bin/sh

#  xcode.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

if [ "$ACTION" = indexbuild ]; then
  # Xcode is preparing the editor by pre-building the project. A formal build takes a while, so we disallow this.
  exit 0
fi

export PATH="/nix/var/nix/profiles/default/bin:$PATH"
export BUILD_ARCHS="$ARCHS"
. ./Tools/core/build.sh
