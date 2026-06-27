{ stdenv, lib, mkShell, autoconf, automake, libtool, pkg-config, nasm }: mkShell {
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
  ++ lib.optionals stdenv.hostPlatform.isx86 [ nasm ];
}
