{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    builder.url = "path:./docker_nix/";
  };

  outputs = inputs@{ self, nixpkgs, builder }:
  let
    lib = inputs.nixpkgs.lib;
    systems = [ "x86_64-linux" "aarch64-linux" ];

    # Build all outputs for a given system. 
    # allow ./image_configs.nix 
    buildOutputs = { system, imageConfigs ? (import ./image_configs.nix) }:
    let
      built = inputs.builder.lib.buildImages { inherit system; image_configs = imageConfigs; };

      # Keep only real image derivations (skip helper scripts)
      imageDrvs = built.packages;

      # Create run scripts for each image
      apps = lib.mapAttrs (name: imageDrv:
        let
          runDrv = built.packages.${name};
        in {
          type = "app";
          program = "${runDrv}/bin/run-${name}";
        }
      ) imageDrvs;

    in {
      inherit apps;
      packages = built.packages;
    };

  in {
    # Per-system packages
    packages = lib.genAttrs systems (system: (buildOutputs { inherit system; }).packages);

    # Per-system apps
    apps = lib.genAttrs systems (system: (buildOutputs { inherit system; }).apps);

    # Reusable packaging logic, so external flakes (e.g. the template) can
    # rebuild these outputs with an overridden imageConfigs.
    lib.buildOutputs = buildOutputs;

    # Build all outputs for an external repo that uses this flake as an input.
    # If imageConfigsPath points at an image config file in that repo, the
    # per-system outputs are rebuilt with it; otherwise the source flake's
    # outputs are passed through unchanged.
    lib.mkOutputs = { imageConfigsPath ? null }:
      let
        imageConfigs = if imageConfigsPath != null && builtins.pathExists imageConfigsPath
                       then import imageConfigsPath
                       else null;

        each = f: builtins.listToAttrs (map (system: {
          name = system;
          value = f (buildOutputs { inherit system imageConfigs; });
        }) systems);
      in
        if imageConfigs == null
        then self.outputs
        else {
          packages = each (o: o.packages);
          apps = each (o: o.apps);
        };

    # Defaults (not setting, to help make incorrect args more explicit).
    # defaultPackage.x86_64-linux = (buildOutputs { system = "x86_64-linux"; }).packages.docker-nix-all;
    # defaultPackage.aarch64-linux = (buildOutputs { system = "aarch64-linux"; }).packages.docker-nix-all;

    # Allow creation of a 'nix template' to help with setup of a clean repository.
    templates = {
      docker-scratch = {
        path = ./templates;
        description = "Docker from scratch template.";
        welcomeText =''
          # Basic nix docker opencode template.

          ## Example use:
          - nix flake show 
          - nix run .#docker-nix-all -- -v ~/.local/share/opencode/auth.json:/home/nixuser/.local/share/opencode/auth.json -v $(pwd)/data/opencode.json:/opencode.json -v $(pwd)/data:/data
          # or
          - chmod u+x ./nix\_docker\_from\_scratch.sh
          - ./nix\_docker\_from\_scratch.sh
        '';
      };
    };

    templates.default = self.outputs.templates.docker-scratch;
  };

}

