#!/bin/sh

#  build-deps.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/3/24.
#

CWD="$(pwd)"
BUILDDIR=build
DEPSDIR="$BUILDDIR/deps"
CFFMPEGDIR=ForwardFFmpeg/Sources/CFFmpeg

OPUS_GIT_TAG=v1.5.2
OPUS_GIT_URL=https://gitlab.xiph.org/xiph/opus.git
OPUS_PATH="$DEPSDIR/opus"
FFMPEG_GIT_COMMIT=358fdf30838682f2b183e67d247e0d4d53b5a6a4
FFMPEG_GIT_URL=https://git.ffmpeg.org/ffmpeg.git
FFMPEG_PATH="$DEPSDIR/ffmpeg"
GAS_PREPROCESSOR_COMMIT=7380ac24e1cd23a5e6d76c6af083d8fc5ab9e943
GAS_PREPROCESSOR_URL=https://github.com/FFmpeg/gas-preprocessor.git
GAS_PREPROCESSOR_PATH="$DEPSDIR/gas-preprocessor"

EXTRA_CFLAGS="-O3"

prefix () {
  local arch="$1"

  echo "$CFFMPEGDIR/$arch"
}

max () {
  local a="$1"
  local b="$2"

  echo "$((a > b ? a : b))"
}

NCPU="$(sysctl -n hw.ncpu)"
NJOB="$(max 1 "$(($NCPU / 2))")"

downloadopus () {
  brew install autoconf automake libtool # Should we pin these?
  git clone --depth=1 --branch="$OPUS_GIT_TAG" "$OPUS_GIT_URL" "$CWD/$OPUS_PATH"
}

downloadgas () {
  git clone "$GAS_PREPROCESSOR_URL" "$CWD/$GAS_PREPROCESSOR_PATH"
  git -C "$CWD/$GAS_PREPROCESSOR_PATH" checkout "$GAS_PREPROCESSOR_COMMIT"
}

downloadffmpeg () {
  git clone "$FFMPEG_GIT_URL" "$CWD/$FFMPEG_PATH"
  git -C "$CWD/$FFMPEG_PATH" checkout "$FFMPEG_GIT_COMMIT"
}

runmake () {
  make -j"$NJOB"
  make install
  make distclean
}

buildopus () {
  local arch="$1"
  echo "Building libopus for $arch"

  cd "$CWD/$OPUS_PATH"
  ./autogen.sh

  # We can configure libopus to build for multiple architectures, but it requires manual code signing to launch the app.
  # If we can figure out how to integrate this script into Xcode's build system to use the relevant code signature, then
  # we can explore such an option.
  ./configure --prefix="$CWD/$(prefix "$arch")" \
    --with-sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --disable-intrinsics --disable-shared \
    --build="$(uname -m)-apple-darwin" \
    --host="$arch-apple-darwin" \
    CC=clang \
    CFLAGS="-arch $arch $EXTRA_CFLAGS" \

  runmake
}

buildgas () {
  local arch="$1"
  local filename=gas-preprocessor.pl
  local bin="$(prefix "$arch")/bin"

  mkdir -p "$CWD/$bin"
  ln -sf "$CWD/$GAS_PREPROCESSOR_PATH/$filename" "$CWD/$bin/$filename"
}

buildffmpeg () {
  local arch="$1"
  echo "Building FFmpeg for $arch"

  local prefix="$(prefix "$arch")"
  cd "$CWD/$FFMPEG_PATH"

  # As of 358fdf3, FFmpeg's C compiler test does not consider sysroot with spaces, and we can't escape it ourselves via
  # quotes or printf. To call this function, make sure Xcode's name does not contain spaces (i.e. prefer "Xcode" or
  # "Xcode-16" instead of "Xcode 16")
  #
  # The following is a list of formats to bundle from the configuration. The actual supported formats may be more, but
  # should not be less. The list is meant to encompass formats supported by the system (e.g. FLAC on macOS), formats
  # supported by X Lossless Decoder (XLD, e.g. WavPack), and formats desirable for users (e.g. Opus).
  #
  # For formats supported by the system, see:
  #
  #   https://developer.apple.com/documentation/audiotoolbox/audio_file_stream_services/1576497-audio_file_types
  #
  # For formats supported by XLD, see:
  #
  #   https://tmkk.undo.jp/xld/index_e.html
  #
  # Demuxers:
  #   aac:       raw ADTS AAC (Advanced Audio Coding)
  #   ac3:       raw AC-3
  #   aiff:      Audio IFF
  #   flac:      raw FLAC
  #   loas:      LOAS AudioSyncStream
  #   matroska:  Matroska / WebM
  #   mjpeg:     raw MJPEG video
  #   mov:       QuickTime / MOV
  #   mp3:       MP2/3 (MPEG audio layer 2/3)
  #   ogg:       Ogg
  #...w64:       Sony Wave64
  #   wav:       WAV / WAVE (Waveform Audio)
  #...wv:        WavPack
  #
  # Decoders:
  #   aac_at:   aac (AudioToolbox)   / Advanced Audio Coding
  #   ac3_at:   ac3 (AudioToolbox)   / Dolby AC-3
  #   alac_at:  alac (AudioToolbox)  / Apple Lossless Audio Codec
  #   eac3_at:  eac3 (AudioToolbox)  / Dolby Digital Plus
  #   libopus:  libopus Opus         / Opus
  #   mjpeg:    MJPEG (Motion JPEG)  / Motion JPEG
  #   mp1_at:   mp1 (AudioToolbox)   / MPEG-1 Audio Layer I
  #   mp2_at:   mp2 (AudioToolbox)   / MPEG-1 Audio Layer II
  #   mp3_at:   mp3 (AudioToolbox)   / MPEG-1 Audio Layer III
  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig" \
  ./configure --prefix="$CWD/$prefix" \
    --disable-network --disable-everything \
    --enable-libopus \
    --enable-demuxer='aac,ac3,aiff,flac,loas,matroska,mov,mp3,ogg,wav' \
    --enable-decoder='*_at,libopus,mjpeg' \
    --enable-protocol='file' \
    --enable-cross-compile \
    --sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --target-os=darwin \
    --arch="$arch" \
    --cc="clang -arch $arch $EXTRA_CFLAGS" \

  runmake
}

build () {
  local arch="$1"
  echo "Building for $arch"

  local PATH="$CWD/$(prefix "$arch")/bin:$PATH"

  buildopus "$arch"
  buildgas "$arch"
  buildffmpeg "$arch"
}

downloadopus
downloadgas
downloadffmpeg

for arch in $ARCHS; do
  build "$arch"
done
