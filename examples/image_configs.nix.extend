# Example 'replacement' image_configs.nix file
# Can remove this file entirely (will revert to remote options)
# Can remove 'base' (and replace with just local image specs)
pkgs:
  let 
    # Including as an example, don't need to include/build on the external 'image_configs.nix' file
    src = builtins.fetchGit {
      url = "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git";
      rev = "e21bf03eb9e4708744f576641b92a054fc6070ee";
    };
    base = (import "${src}/image_configs.nix") pkgs;

    # Lists of packages.
    my_packages = (with pkgs; [
      hello
    ]);

  in
  base // {
    image_specs = base.image_specs // {
      docker-nix-hello = {
        contents = my_packages;
        config = { 
          # Overriding 'pkgs.dockerTools.buildLayeredImage' config options for this image
          allowUnfree = true;
        };
      };
    };
  }
