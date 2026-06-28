{ fetchNpmPackage, fetchFromGitHub }: fetchNpmPackage {
  name = "opensubsonic-openapi";
  strictDeps = true;
  src = fetchFromGitHub {
    owner = "opensubsonic";
    repo = "open-subsonic-api";
    rev = "7eed79524b218236d81a975d13c4ba29b4ea1d7e";
    hash = "sha256-IoDEoh58OqiixLu8n3N/G9Fzqm4WYoTuGZLTLGw7XfM=";
  };
  npmBuildScript = "build:openapi";
}
