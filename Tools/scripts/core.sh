#!/bin/sh

#  core.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/9/24.
#

export CWD="$(pwd)"
export EXTRA_CFLAGS=""

if [ "$CONFIGURATION" != "Debug" ]; then
  export EXTRA_CFLAGS="-O3"
fi

max () {
  local a="$1"
  local b="$2"

  echo "$((a > b ? a : b))"
}
