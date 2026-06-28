{ buildNpmPackage, fetchFromGitHub, cacert }: buildNpmPackage {
  name = "opensubsonic-openapi";
  strictDeps = true;
  src = fetchFromGitHub {
    owner = "opensubsonic";
    repo = "open-subsonic-api";
    rev = "e184c37c3485cdb6afa57ae86b89c9d99e2f1105";
    hash = "sha256-oYiab/O5K3y01ZsgApZW+KCgtgAAdYuuB2dLQ6DPAzc=";
  };
  nativeBuildInputs = [cacert];
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  npmDepsHash = "sha256-d7GDnywwJgIRF3lpgrD9MQlGq0+50oRZZyY/csJjIMM=";
  npmBuildScript = "build:openapi";
  installPhase = ''
    runHook preInstall
    cp content/en/docs/Openapi/openapi.json $out
    runHook postInstall
  '';
}
