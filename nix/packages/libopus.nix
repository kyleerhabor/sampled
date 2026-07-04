{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config }: stdenv.mkDerivation {
  pname = "libopus";
  version = "v1.6.1+";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "opus";
    rev = "3da9f7a6db1c05c3996cb363a9d1931a978bf1be";
    hash = "sha256-VdJhdy9ZwWP0oxoz6OfjCpgYaEkrEH2Y78/TT2VNPYU=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
    "--disable-dependency-tracking"
    "--disable-doc"
    "--disable-extra-programs"
  ];

  # Build
  enableParallelBuilding = true;
}
