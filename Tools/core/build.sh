#!/bin/sh

#  build.sh
#  Sampled
#
#  Created by Kyle Erhabor on 6/27/26.
#

nix_options=

if [ "${BUILD_DRY_RUN}" = 1 ]; then
  nix_options="--dry-run"
fi

if [ "${BUILD_VERBOSE}" = 1 ]; then
  nix_options="$nix_options --print-build-logs"
fi

nix_pkgs=

for arch in $BUILD_ARCHS; do
  case "$arch" in
    x86_64) nix_pkgs="$nix_pkgs .#packages.x86_64-darwin.cffmpeg" ;;
    arm64) nix_pkgs="$nix_pkgs .#packages.aarch64-darwin.cffmpeg" ;;
    *)
      echo "Unknown architecture: $arch" >&2
      exit 1
      ;;
  esac
done

echo "Building dependencies..."
nix build --impure --no-link $nix_options $nix_pkgs ".#opensubsonic-openapi"
