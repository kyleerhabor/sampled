#!/bin/sh

#  xcode-setup.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

if [ -z "${PROJECT_DIR:-}" ]; then
  echo "This script should not be run manually. Did you mean to run setup.sh instead?" >&2
  exit 1
fi

. ./Tools/core/setup/xcode.sh
