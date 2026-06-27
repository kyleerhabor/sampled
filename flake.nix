{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };
  outputs = { self, nixpkgs }: let
    # Nixpkgs has this note:
    #
    #   evaluation warning: Nixpkgs 26.05 will be the last release to support x86_64-darwin; see https://nixos.org/manual/nixpkgs/unstable/release-notes#x86_64-darwin-26.05
    #
    # In the future, we may be required to cross-compile x86_64 from arm64 and pin dependencies like the Apple SDK. The
    # worst-case scenario is that cross compiling is slow (~40 minutes).
    systems = ["x86_64-darwin" "aarch64-darwin"];
    forDarwin = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      if system == builtins.currentSystem
      then nixpkgs.legacyPackages.${system}
      else nixpkgs.legacyPackages.${builtins.currentSystem}.pkgsCross.${system};
  in {
    packages = forDarwin (
      system: let pkgs = pkgsFor system; in {
        # If the remote is unavailable, just replace it with its GitHub mirror.
        libogg = pkgs.callPackage ./nix/packages/libogg.nix {};
        libvorbis = pkgs.callPackage ./nix/packages/libvorbis.nix {
          libogg = self.packages.${system}.libogg;
        };
        libopus = pkgs.callPackage ./nix/packages/libopus.nix {};
        ffmpeg = pkgs.callPackage ./nix/packages/ffmpeg.nix {
          libogg = self.packages.${system}.libogg;
          libvorbis = self.packages.${system}.libvorbis;
          libopus = self.packages.${system}.libopus;
        };
        cffmpeg-support = pkgs.buildPackages.runCommand "cffmpeg-support" {} "cp -R ${./SampledCore/Sources/CFFmpegSupport}/. $out";
        cffmpeg = pkgs.symlinkJoin {
          name = "cffmpeg";
          paths = [
            self.packages.${system}.cffmpeg-support
            self.packages.${system}.libogg
            self.packages.${system}.libvorbis
            self.packages.${system}.libopus
            self.packages.${system}.ffmpeg
          ];
        };
      }
    );
    devShells = forDarwin (
      system: let pkgs = pkgsFor system; in {
        default = pkgs.callPackage ./nix/devShell.nix {};
      }
    );
  };
}
