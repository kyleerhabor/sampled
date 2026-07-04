{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config }: stdenv.mkDerivation {
  pname = "libogg";
  version = "v1.3.6+";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "ogg";
    rev = "06a5e0262cdc28aa4ae6797627a783b5010440f0";
    hash = "sha256-neCZLIrl3Uw58/N3FM3pm6Y7gV8WuVmJgfs9wfTK1to=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
    "--disable-dependency-tracking"
  ];

  # Build
  enableParallelBuilding = true;
}
