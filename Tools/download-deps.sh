#!/bin/sh

#  download-deps.sh
#  Sampled
#
#  Created by Kyle Erhabor on 10/9/24.
#

. "$(dirname "$0")/scripts/core.sh"
. "$(dirname "$0")/scripts/build.sh"

OGG_GIT_COMMIT=7cf42ea17aef7bc1b7b21af70724840a96c2e7d0 # v1.3.5+
OGG_GIT_URL=https://gitlab.xiph.org/xiph/ogg.git
VORBIS_GIT_COMMIT=bb4047de4c05712bf1fd49b9584c360b8e4e0adf # v1.3.7+
VORBIS_GIT_URL=https://gitlab.xiph.org/xiph/vorbis.git
OPUS_GIT_COMMIT=7db26934e4156597cb0586bb4d2e44dccdde1a59 # v1.5.2+
OPUS_GIT_URL=https://gitlab.xiph.org/xiph/opus.git
FFMPEG_GIT_COMMIT=e35587250c3e036261ea9cfc266e74730b6f60ae # v7.1+
FFMPEG_GIT_URL=https://git.ffmpeg.org/ffmpeg.git

gitdownload () {
  local remote="$1"
  local branch="$2"
  local path="$3"

  git -C "$path" fetch "$remote" || git clone "$remote" "$path"
  git -C "$path" checkout "$branch"
}

downloadbrew () {
  brew install autoconf automake libtool nasm
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
