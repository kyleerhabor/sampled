#!/bin/sh

#  ffmpeg.sh
#  Sampled
#
#  Created by Kyle Erhabor on 11/8/24.
#  

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

build () {
  local arch="$1"

  echo "Building FFmpeg for $arch"

  local prefix="$(prefixarch "$arch")"
  local PKG_CONFIG_PATH="$CWD/$prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
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
  # The format is "[ID]: [Description] / [Name]" where [Name] refers to a common name. A prefix of "..." means the label
  # has not been tested yet.
  #
  # Demuxers:
  #   aac:       raw ADTS AAC (Advanced Audio Coding)
  #   ac3:       raw AC-3
  #   aiff:      Audio IFF
  #   asf:       ASF (Advanced / Active Streaming Format)
  #   flac:      raw FLAC
  #   loas:      LOAS AudioSyncStream
  #   matroska:  Matroska / WebM
  #   mov:       QuickTime / MOV
  #   mp3:       MP2/3 (MPEG audio layer 2/3)
  #   ogg:       Ogg
  #   w64:       Sony Wave64
  #   wav:       WAV / WAVE (Waveform Audio)
  #   wv:        WavPack
  #
  # Decoders:
  #   aac_at:     aac (AudioToolbox)                         / Advanced Audio Coding
  #   ac3_at:     ac3 (AudioToolbox)                         / Dolby AC-3
  #   alac_at:    alac (AudioToolbox)                        / Apple Lossless Audio Codec
  #   eac3_at:    eac3 (AudioToolbox)                        / Dolby Digital Plus
  #   flac:       FLAC (Free Lossless Audio Codec)           / Free Lossless Audio Codec
  #   libopus:    libopus Opus                               / Opus
  #   mjpeg:      MJPEG (Motion JPEG)                        / Motion JPEG
  #   msmpeg4v3:  MPEG-4 part 2 Microsoft variant version 3  / Microsoft MPEG-4
  #...mp1_at:     mp1 (AudioToolbox)                         / MPEG-1 Audio Layer I
  #   mp2_at:     mp2 (AudioToolbox)                         / MPEG-1 Audio Layer II
  #   mp3_at:     mp3 (AudioToolbox)                         / MPEG-1 Audio Layer III
  #   pcm_f32le:  PCM 32-bit floating point little-endian    / Sony Wave64 & Waveform Audio File Format
  #   pcm_f32be:  PCM 32-bit floating point big-endian       / Audio Interchange File Format
  #   pcm_s8:     PCM signed 8-bit                           / Audio Interchange File Format & Waveform Audio File Format
  #   pcm_s16le:  PCM signed 16-bit little-endian            / Sony Wave64 & Waveform Audio File Format
  #   pcm_s16be:  PCM signed 16-bit big-endian               / Audio Interchange File Format
  #   pcm_s24le:  PCM signed 24-bit little-endian            / Sony Wave64 & Waveform Audio File Format
  #   pcm_s24be:  PCM signed 24-bit big-endian               / Audio Interchange File Format
  #   pcm_s32le:  PCM signed 32-bit little-endian            / Sony Wave64 & Waveform Audio File Format
  #   pcm_s32be:  PCM signed 32-bit big-endian               / Audio Interchange File Format
  #   png:        PNG (Portable Network Graphics) image      / PNG
  #   vorbis:     Vorbis                                     / Vorbis
  #   wavpack:    WavPack                                    / WavPack
  #   wmav2:      Windows Media Audio 2                      / Windows Media Audio
  ./configure --prefix="$CWD/$prefix" \
    --disable-network --disable-everything \
    --enable-libopus --enable-libvorbis \
    --enable-demuxer=aac,ac3,aiff,asf,flac,loas,matroska,mov,mp3,ogg,w64,wav,wv \
    --enable-decoder=*_at,flac,libopus,mjpeg,msmpeg4v3,pcm_f32le,pcm_f32be,pcm_s8,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,png,vorbis,wavpack,wmav2 \
    --enable-protocol=file \
    --disable-shared --enable-static \
    --arch="$arch" \
    --enable-cross-compile \
    --sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
    --target-os=darwin \
    --cc="clang -arch $arch $EXTRA_CFLAGS" \
    --extra-cflags="-I$CWD/$prefix/include" \
    --extra-ldflags="-L$CWD/$prefix/lib"

  runmake
  popd
}
