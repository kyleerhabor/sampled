{ stdenv, fetchFromGitLab, autoreconfHook, pkg-config }: stdenv.mkDerivation {
  name = "libogg";
  version = "v1.3.6+";
  strictDeps = true;
  src = fetchFromGitLab {
    domain = "gitlab.xiph.org";
    owner = "xiph";
    repo = "ogg";
    rev = "0288fadac3ac62d453409dfc83e9c4ab617d2472";
    hash = "sha256-IoDEoh58OqiixLu8n3N/G9Fzqm4WYoTuGZLTLGw7XfM=";
  };

  # Configure
  nativeBuildInputs = [autoreconfHook pkg-config];
  dontDisableStatic = true;
  configureFlags = [
    "--disable-shared"
  ];

  # Build
  enableParallelBuilding = true;
}
