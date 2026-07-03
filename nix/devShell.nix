{
  stdenv,
  lib,
  mkShell,
  autoconf,
  automake,
  libtool,
  pkg-config,
  nasm,
  libopus-src,
  libvorbis-src,
  libogg-src,
  ffmpeg-src,
}: mkShell {
  # From Vorbis:
  #
  #   Development source is under git revision control at https://gitlab.xiph.org/xiph/vorbis.git. You will also need
  #   the newest versions of autoconf, automake, libtool and pkg-config in order to compile Vorbis from development source.
  #
  # From Opus:
  #
  #   On Apple macOS, install Xcode and brew.sh, then in the Terminal enter:
  #
  #       % brew install autoconf automake libtool
  #
  # From FFmpeg:
  #
  #   Mac OS X on amd64 and x86 requires nasm to build most of the optimized assembly functions.
  buildInputs = [
    autoconf
    automake
    libtool
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isx86 [nasm];
  shellHook = ''
    export_src() {
      local name="$1"
      local path="$2"

      export "$name=$path"
      echo "export $name=$path"
    }

    export_src FFMPEG_SRC ${ffmpeg-src}
    export_src LIBOGG_SRC ${libogg-src}
    export_src LIBVORBIS_SRC ${libvorbis-src}
    export_src LIBOPUS_SRC ${libopus-src}

    srchelp () {
      local src=$1
      local dir=$(mktemp -d)

      if [ -z "$src" ]; then
        echo "Usage: srchelp <src>"
        return 1
      fi

      cp -r "$src"/* "$dir/"
      chmod -R u+w "$dir"
      cd "$dir"
      autoreconf -fi
      ./configure --help
      rm -rf "$dir"
    }
  '';
}
