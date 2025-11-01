#!/bin/sh

#  xcode.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#

# We're using sh, so we don't have whatever Zsh or Bash sources.

homebrew_prefix () {
  local prefix="$1"

  if [ -x "$prefix/bin/brew" ]; then
    echo "$prefix"
  fi
}

if ! command -v brew > /dev/null; then
  HOMEBREW_PREFIX="$(homebrew_prefix /opt/homebrew)"

  if [ -z "$HOMEBREW_PREFIX" ]; then
    echo "Homebrew not found" >&2
    exit 1
  fi

  eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"
fi

if [ "$CONFIGURATION" = "Release" ]; then
  export EXTRA_CFLAGS="-O3"
  export EXTRA_FFMPEGFLAGS=(--disable-programs --disable-doc)
fi
