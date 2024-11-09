#!/bin/sh

#  core.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

export CWD="$(pwd)"

max () {
  local a="$1"
  local b="$2"

  echo "$((a > b ? a : b))"
}

prefix () {
  local prefix="$1"
  local coll="$2"
  read -ra archs <<< "$coll"

  for item in "${archs[@]}"; do
    echo "$prefix $item \c"
  done
}
