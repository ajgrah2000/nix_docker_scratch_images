# Originally created using a command similar to:
# nix flake init -t "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git" --refresh
{
  inputs = {
    # 'local store' can be useful altering the base nix setup.
    # local-src.url = "git+file:./nix_docker_scratch_images";
    remote-src.url = "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git?ref=main";
  };

  outputs = { self, remote-src, ... }:
    let
      # Select as 'remote or local'.
      flake-source = remote-src;
    in
      # Rebuild outputs with a local image_configs.nix if present, else passthrough.
      flake-source.lib.mkOutputs { imageConfigsPath = ./image_configs.nix; };
}
