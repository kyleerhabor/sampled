{ stdenv, lib, buildPackages, fetchgit, pkg-config, nasm, zlib, libvorbis, libopus }: let
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
  demuxers = [
    # System
    "aac" "ac3" "aiff" "caf" "eac3" "flac" "loas" "mov" "mp3" "w64" "wav"

    # XLD
    "ogg" "wv"

    # Project
    "asf" "avi" "matroska"

    # Maybe
    # "ape" "dsf" "shn" "tak" "tta"
  ];
  decoders = [
    # Dependencies
    "libopus" "libvorbis"

    # Native
    "flac" "mjpeg" "png" "wavpack" "wmav2"

    # Audio Toolbox
    "aac_at" "ac3_at" "adpcm_ima_qt_at" "alac_at" "amr_nb_at" "eac3_at" "gsm_ms_at" "ilbc_at" "mp1_at" "mp2_at" "mp3_at"
    "pcm_alaw_at" "pcm_mulaw_at" "qdm2_at" "qdmc_at"

    # PCM: floating point
    "pcm_f16le" "pcm_f24le" "pcm_f32be" "pcm_f32le" "pcm_f64be" "pcm_f64le"

    # PCM: signed
    #
    # All demuxers produce interleaved audio, so the planar variants aren't necessary.
    "pcm_s16be" "pcm_s16le" "pcm_s24be" "pcm_s24le" "pcm_s32be" "pcm_s32le" "pcm_s64be" "pcm_s64le" "pcm_s8"

    # PCM: unsigned
    "pcm_u16be" "pcm_u16le" "pcm_u24be" "pcm_u24le" "pcm_u32be" "pcm_u32le" "pcm_u8"
  ];
in stdenv.mkDerivation {
  pname = "ffmpeg";
  version = "8.0+";
  strictDeps = true;
  src = fetchgit {
    url = "https://git.ffmpeg.org/ffmpeg.git";
    rev = "a37171bed554305b7b83c521ccd25ef40806347f";
    hash = "sha256-pM7+SJu2OQDahToA77j3CNN8zPXiUQAKebGmyN42SEM=";
  };

  # Configure
  nativeBuildInputs = [pkg-config]
    ++ lib.optionals stdenv.hostPlatform.isx86 [nasm];
  # The png decoder depends on zlib, which must be linked.
  buildInputs = [zlib libvorbis libopus];
  dontDisableStatic = true;
  configurePlatforms = [];
  configureFlags = [
    # Configuration
    "--disable-checkasm"
    "--disable-shared"
    "--enable-static"

    # Programs
    "--disable-programs"
    "--enable-ffprobe"

    # Documentation
    "--disable-doc"

    # Components
    "--disable-network"

    # Individual components
    "--disable-everything"
    "--enable-demuxer=${builtins.concatStringsSep "," demuxers}"
    "--enable-decoder=${builtins.concatStringsSep "," decoders}"
    "--enable-protocol=file"

    # External libraries
    "--enable-libopus"
    "--enable-libvorbis"

    # Toolchain
    "--arch=${stdenv.hostPlatform.parsed.cpu.name}"
    "--target-os=${stdenv.hostPlatform.parsed.kernel.name}"
    "--pkg-config-flags=--static"
  ]
  ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    # Toolchain
    "--enable-cross-compile"
    "--cross-prefix=${stdenv.cc.targetPrefix}"
    "--host-cc=${buildPackages.stdenv.cc}/bin/cc"
  ];
  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --cc=$CC $configureFlags
    runHook postConfigure
  '';

  # Build
  enableParallelBuilding = true;
}
