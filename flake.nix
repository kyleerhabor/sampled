{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };
  outputs = { self, nixpkgs }: let
    # Nixpkgs has this note:
    #
    #   evaluation warning: Nixpkgs 26.05 will be the last release to support x86_64-darwin; see https://nixos.org/manual/nixpkgs/unstable/release-notes#x86_64-darwin-26.05
    #
    # I think pinning Nixpkgs to 26.05 should suppress the issue, but risks breaking in the future.
    systems = ["x86_64-darwin" "aarch64-darwin"];
    forDarwin = nixpkgs.lib.genAttrs systems;
    nativePkgs = import nixpkgs {
      system = builtins.currentSystem;
      config.allowDeprecatedx86_64Darwin = true;
    };
    pkgsFor = system:
      if system == builtins.currentSystem
      then nativePkgs
      else nativePkgs.pkgsCross.${system};
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
          libvorbis = self.packages.${system}.libvorbis;
          libopus = self.packages.${system}.libopus;
        };
        opensubsonic-openapi = pkgs.callPackage ./nix/packages/opensubsonic-openapi.nix {};
        cffmpeg-support = pkgs.buildPackages.runCommand "cffmpeg-support" {} "cp -R ${./SampledCore/Sources/CFFmpegSupport}/. $out";
        cffmpeg = pkgs.symlinkJoin {
          name = "cffmpeg";
          paths = [
            self.packages.${system}.cffmpeg-support
            self.packages.${system}.ffmpeg
          ];
          postBuild = ''
            # We don't use this for anything, but it makes it easier to find the source code for these libraries.
            mkdir $out/src
            ln -sfn ${self.packages.${system}.ffmpeg.src} $out/src/ffmpeg
            ln -sfn ${self.packages.${system}.libogg.src} $out/src/libogg
            ln -sfn ${self.packages.${system}.libvorbis.src} $out/src/libvorbis
            ln -sfn ${self.packages.${system}.libopus.src} $out/src/libopus
          '';
        };
      }
    );
    devShells = forDarwin (
      system: let pkgs = pkgsFor system; in {
        default = pkgs.callPackage ./nix/devShell.nix {
          libogg-src = self.packages.${system}.libogg.src;
          libvorbis-src = self.packages.${system}.libvorbis.src;
          libopus-src = self.packages.${system}.libopus.src;
          ffmpeg-src = self.packages.${system}.ffmpeg.src;
        };
      }
    );
  };
}
