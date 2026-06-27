{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config, libogg }: stdenv.mkDerivation {
  name = "libvorbis";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "vorbis";
    rev = "2d79800b6751dddd4b8b4ad50832faa5ae2a00d9";
    hash = "sha256-zpV37LIq571Z0li+Prqu3Zcb0I4Y4iLC8u58udadNnE=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  buildInputs = [libogg];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
  ];
  postAutoreconf = ''
    # Remove obsolete -force_cpusubtype_ALL option so it's not passed to ld.
    #
    # https://github.com/Homebrew/homebrew-core/blob/35ebe9ef7f7f78c7e5ca425b6c90415c608788ab/Formula/lib/libvorbis.rb#L49
    substituteInPlace configure --replace-fail '-force_cpusubtype_ALL' ""
  '';

  # Build
  enableParallelBuilding = true;
}
