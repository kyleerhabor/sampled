#!/bin/sh

#  build.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

set -e

nix_options=

if [ "${BUILD_DRY_RUN}" = 1 ]; then
  nix_options="--dry-run"
fi

for arch in $BUILD_ARCHS; do
  echo "Building CFFmpeg for $arch..."

  case "$arch" in
    x86_64) pkg=".#packages.x86_64-darwin.cffmpeg" ;;
    arm64) pkg=".#packages.aarch64-darwin.cffmpeg" ;;
    *)
      echo "Unknown architecture: $arch" >&2
      exit 1
      ;;
  esac

  nix build --impure ${nix_options} "$pkg" \
    -o "SampledCore/Sources/CFFmpeg/$arch"
done

echo "Building OpenSubsonic OpenAPI specification..."
nix build --impure ${nix_options} ".#opensubsonic-openapi" \
  -o "SampledCore/Sources/SampledOpenSubsonicAPI/openapi.json"
