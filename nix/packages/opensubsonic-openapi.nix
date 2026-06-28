{ buildNpmPackage, fetchFromGitHub, cacert }: buildNpmPackage {
  name = "opensubsonic-openapi";
  strictDeps = true;
  src = fetchFromGitHub {
    owner = "kyleerhabor";
    repo = "open-subsonic-api";
    rev = "12f557ebdf195bf429d52134832ae8a87f02b754";
    hash = "sha256-dABzOQb2uoCBQreMUtNQQIPLbwJl38xgquimRjaRBzU=";
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
