#!/bin/sh

#  install.sh
#  Sampled
#
#  Created by Kyle Erhabor on 7/3/26.
#

if [ "${BUILD_DRY_RUN}" = 1 ]; then
  exit 0
fi

for arch in $BUILD_ARCHS; do
  case "$arch" in
    x86_64) system="x86_64-darwin" ;;
    arm64) system="aarch64-darwin" ;;
  esac

  echo "Installing CFFmpeg for $arch..."
  ln -fhs "$(nix eval --impure --raw ".#packages.$system.cffmpeg.outPath")" "SampledCore/Sources/CFFmpeg/$arch"
done

echo "Installing OpenSubsonic OpenAPI specification..."
ln -fhs "$(nix eval --impure --raw .#opensubsonic-openapi.outPath)" \
  "SampledCore/Sources/SampledOpenSubsonicAPI/openapi.json"
