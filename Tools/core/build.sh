#!/bin/sh

#  build.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

for arch in $ARCHS; do
  echo "Building CFFmpeg for $arch..."

  case "$arch" in
    x86_64) pkg=".#packages.x86_64-darwin.cffmpeg" ;;
    arm64) pkg=".#packages.aarch64-darwin.cffmpeg" ;;
    *)
      echo "Unknown architecture: $arch" >&2
      exit 1
      ;;
  esac

  nix build --impure "$pkg" -o "SampledCore/Sources/CFFmpeg/$arch"
done

echo "Building OpenSubsonic OpenAPI specification..."
nix build --impure ".#opensubsonic-openapi" -o "SampledCore/Sources/SampledOpenSubsonicAPI/openapi.json"
