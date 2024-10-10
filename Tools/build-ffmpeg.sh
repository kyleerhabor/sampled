#!/bin/sh

#  build-ffmpeg.sh
#  Forward
#
#  Created by Kyle Erhabor on 10/9/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  local arch="$1"
  echo "Building FFmpeg for $arch"

  local PATH="$CWD/$(prefix "$arch")/bin:$PATH"
  local prefix="$(prefix "$arch")"
  pushd "$CWD/$FFMPEGDIR"

  # As of 358fdf3, FFmpeg's C compiler test does not consider sysroot with spaces, and we can't escape it ourselves via
  # quotes or printf. To call this function, make sure Xcode's name does not contain spaces (i.e. prefer "Xcode" or
  # "Xcode-16" instead of "Xcode 16")
  #
  # The following is a list of formats to bundle from the configuration. The actual supported formats may be more, but
  # should not be less. The list is meant to encompass formats supported by the system (e.g. AAC on macOS), formats
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
  #   aac_at:   aac (AudioToolbox)                     / Advanced Audio Coding
  #   ac3_at:   ac3 (AudioToolbox)                     / Dolby AC-3
  #   alac_at:  alac (AudioToolbox)                    / Apple Lossless Audio Codec
  #   eac3_at:  eac3 (AudioToolbox)                    / Dolby Digital Plus
  #   libopus:  libopus Opus                           / Opus
  #   mjpeg:    MJPEG (Motion JPEG)                    / Motion JPEG
  #   mp1_at:   mp1 (AudioToolbox)                     / MPEG-1 Audio Layer I
  #   mp2_at:   mp2 (AudioToolbox)                     / MPEG-1 Audio Layer II
  #   mp3_at:   mp3 (AudioToolbox)                     / MPEG-1 Audio Layer III
  #   png:      PNG (Portable Network Graphics) image  / PNG
  PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig" \
  ./configure --prefix="$CWD/$prefix" \
    --disable-network --disable-everything \
    --enable-libopus \
    --enable-demuxer='aac,ac3,aiff,flac,loas,matroska,mov,mp3,ogg,wav' \
    --enable-decoder='*_at,libopus,mjpeg,png' \
    --enable-protocol='file' \
    --enable-cross-compile \
    --sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --target-os=darwin \
    --arch="$arch" \
    --cc="clang -arch $arch $EXTRA_CFLAGS" \

  runmake
  popd
}

for arch in $ARCHS; do
  build "$arch"
done
