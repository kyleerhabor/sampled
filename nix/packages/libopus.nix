{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config }: stdenv.mkDerivation {
  name = "libopus";
  version = "v1.5.2+";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "opus";
    rev = "2d862ea14b233e5a3f3afaf74d96050691af3cd5";
    hash = "sha256-yCoFVs5YMITB1vE8Y/KvnHLnqDZqIKts/Sr5ZJNAgj4=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
    "--enable-check-asm"
    "--disable-doc"
    "--disable-extra-programs"
  ];

  # Build
  enableParallelBuilding = true;
}
