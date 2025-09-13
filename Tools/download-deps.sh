#!/bin/sh

#  download-deps.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

set -e

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

OGG_GIT_COMMIT=0288fadac3ac62d453409dfc83e9c4ab617d2472 # v1.3.6+
OGG_GIT_URL=https://gitlab.xiph.org/xiph/ogg.git
VORBIS_GIT_COMMIT=43bbff0141028e58d476c1d5fd45dd5573db576d # v1.3.7+
VORBIS_GIT_URL=https://gitlab.xiph.org/xiph/vorbis.git
OPUS_GIT_COMMIT=f92fdda4f9b75ecb5f0f38b86c991195585579ea # v1.5.2+
OPUS_GIT_URL=https://gitlab.xiph.org/xiph/opus.git
FFMPEG_GIT_COMMIT=a4fd3f27f4d911e807f9c45931a5fd5d3ae95c87 # v8.0.0+
FFMPEG_GIT_URL=https://git.ffmpeg.org/ffmpeg.git

gitdownload () {
  local remote="$1"
  local branch="$2"
  local path="$3"

  git -C "$path" fetch "$remote" || git clone "$remote" "$path" || true
  git -C "$path" checkout "$branch"
}

downloadbrew () {
  brew install autoconf automake libtool nasm wget pkgconf
}

downloadogg () {
  gitdownload "$OGG_GIT_URL" "$OGG_GIT_COMMIT" "$CWD/$OGGDIR"
}

downloadvorbis () {
  gitdownload "$VORBIS_GIT_URL" "$VORBIS_GIT_COMMIT" "$CWD/$VORBISDIR"
}

downloadopus () {
  gitdownload "$OPUS_GIT_URL" "$OPUS_GIT_COMMIT" "$CWD/$OPUSDIR"
}

downloadffmpeg () {
  gitdownload "$FFMPEG_GIT_URL" "$FFMPEG_GIT_COMMIT" "$CWD/$FFMPEGDIR"
}

downloadbrew
downloadogg
downloadvorbis
downloadopus
downloadffmpeg
