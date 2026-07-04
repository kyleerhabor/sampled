{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config, libogg }: stdenv.mkDerivation {
  pname = "libvorbis";
  version = "v1.3.7+";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "vorbis";
    rev = "e3c9861ff096d52378e131ff8c334552e09cdffa";
    hash = "sha256-JbPSiwXvgQ2t/EtyjmiEEVye7M/sIG9gMk3IZRvBQWc=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  propagatedBuildInputs = [libogg];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
    "--disable-dependency-tracking"
    "--disable-oggtest"
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
