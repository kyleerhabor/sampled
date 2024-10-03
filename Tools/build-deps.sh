#!/bin/sh

#  build-deps.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/3/24.
#

DEPSDIR=deps
CFFMPEGDIR=ForwardFFmpeg/Sources/CFFmpeg

OPUS_GIT_TAG=v1.5.2
OPUS_GIT_URL=https://gitlab.xiph.org/xiph/opus.git
OPUS_PATH="$DEPSDIR/opus"
FFMPEG_GIT_COMMIT=358fdf30838682f2b183e67d247e0d4d53b5a6a4
FFMPEG_GIT_URL=https://git.ffmpeg.org/ffmpeg.git
FFMPEG_PATH="$DEPSDIR/ffmpeg"
GAS_PREPROCESSOR_COMMIT=7380ac24e1cd23a5e6d76c6af083d8fc5ab9e943
GAS_PREPROCESSOR_URL=https://github.com/FFmpeg/gas-preprocessor
GAS_PREPROCESSOR_PATH="$DEPSDIR/gas-preprocessor"

CWD="$(pwd)"

max () {
  local a="$1"
  local b="$2"

  echo "$((a > b ? a : b))"
}

NCPU="$(sysctl -n hw.ncpu)"
NJOB="$(max 1 "$(($NCPU / 2))")"

runmake () {
  make -j"$NJOB"
  make install
}

downloadopus () {
  brew install autoconf automake libtool # Should we pin these?
  git -C clone --depth=1 --branch="$OPUS_GIT_TAG" "$OPUS_GIT_URL" "$CWD/$OPUS_PATH"
}

downloadgas () {
  git clone "$GAS_PREPROCESSOR_URL" "$CWD/$GAS_PREPROCESSOR_PATH"
  git -C "$CWD/$GAS_PREPROCESSOR_PATH" checkout "$GAS_PREPROCESSOR_COMMIT"
}

downloadffmpeg () {
  git clone "$FFMPEG_GIT_URL" "$CWD/$FFMPEG_PATH"
  git -C "$CWD/$FFMPEG_PATH" checkout "$FFMPEG_GIT_COMMIT"
}

prefix () {
  local arch="$1"

  echo "$CFFMPEGDIR/$arch"
}

buildopus () {
  local arch="$1"
  echo "Building libopus for $arch"

  cd "$CWD/$OPUS_PATH"
  "$CWD/$OPUS_PATH/autogen.sh"
  "$CWD/$OPUS_PATH/configure" --prefix="$CWD/$(prefix "$arch")" --disable-shared
  runmake
}

buildgas () {
  local arch="$1"

  ln "$CWD/$GAS_PREPROCESSOR_PATH/gas-preprocessor.pl" "$CWD/$(prefix "$arch")/bin"
}

buildffmpeg () {
  cd "$CWD/$FFMPEG_PATH"

  local arch="$1"
  echo "Building FFmpeg for $arch"

  local prefix="$(prefix "$arch")"

  # As of 358fdf3, FFmpeg's C compiler test does not consider sysroot with spaces, and we can't escape it ourselves via
  # quotes or printf. To call this function, make sure Xcode's name does not contain spaces (i.e. prefer "Xcode" or
  # "Xcode-16" instead of "Xcode 16")
  #
  # The following processors is a list of desired formats from the configuration. The actual supported formats may be
  # more, but should not be less.
  #
  # Demuxers:
  #   aac:       AAC (Advanced Audio Coding)
  #   flac:      FLAC
  #   matroska:  Matroska / WebM
  #   mov:       QuickTime / MOV
  #   mp3:       MP2/3 (MPEG audio layer 2/3)
  #   ogg:       Ogg
  #
  # Decoders:
  #   aac_at:   aac (AudioToolbox)                / Advanced Audio Coding
  #   ac3_at:   ac3 (AudioToolbox)                / Dolby AC-3
  #   alac_at:  alac (AudioToolbox)               / Apple Lossless Audio Codec
  #   eac3_at:  eac3 (AudioToolbox)               / Dolby Digital Plus
  #   flac:     FLAC (Free Lossless Audio Codec)  / Free Lossless Audio Codec
  #   mp1_at:   mp1 (AudioToolbox)                / MPEG-1 Audio Layer I
  #   mp2_at:   mp2 (AudioToolbox)                / MPEG-1 Audio Layer II
  #   mp3_at:   mp3 (AudioToolbox)                / MPEG-1 Audio Layer III
  #   libopus:  libopus Opus                      / Opus
  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig" "$CWD/$FFMPEG_PATH/configure" --prefix="$CWD/$prefix" \
    --disable-network --disable-everything \
    --enable-libopus \
    --enable-demuxer='aac,flac,matroska,mov,mp3,ogg' \
    --enable-decoder='*_at,flac,libopus' \
    --enable-protocol='file' \
    --arch="$arch" \
    --enable-cross-compile \
    --sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --target-os=darwin \
    --cc="clang -arch $arch" \
    --enable-static

  runmake
}

downloadopus
downloadgas
downloadffmpeg

echo 'Building for x86_64'

PATH="$CWD/$(prefix x86_64)/bin:$PATH"
buildopus x86_64
buildgas x86_64
buildffmpeg x86_64
