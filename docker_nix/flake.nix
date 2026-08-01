{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      buildImages = { system, image_configs }:

      let
        # Shared nixpkgs set for images that don't need a custom nixpkgs config.
        basePkgs = nixpkgs.legacyPackages.${system};

        # Base image configs evaluated with the shared pkgs.
        baseSpecs = image_configs basePkgs;

        runScript = name: imageDrv:
          basePkgs.writeShellScriptBin "run-${name}" ''
            set -e

            IMAGE_NAME="${name}"

            echo "Loading Docker image: $IMAGE_NAME"
            docker load < ${imageDrv}

            echo "Running container: $IMAGE_NAME $@"
            docker run "$@" --rm -it "$IMAGE_NAME"
          '';

        buildLayeredImage = name: image_specs:
          let
            # If this spec carries a nixpkgs config (e.g. allowUnfree), re-evaluate
            # the image configs with a nixpkgs instance that has it. Packages are
            # validated (unfree, etc.) when their derivation is created, so the
            # spec's contents must come from that configured instance.
            pkgs = if image_specs ? config
                   then import nixpkgs { inherit system; config = image_specs.config; }
                   else basePkgs;

            image_specs' = if image_specs ? config
                           then (image_configs pkgs).image_specs.${name}
                           else image_specs;

            extraContents = image_specs'.contents;
            entrypoint = "/bin/entrypoint";
            extraConfig = if image_specs' ? config then image_specs'.config else {};

            # This package list is intended to be packages that 'must exist'
            # for the docker build to occur (essentially all commands in here).
            minimal_packages = with pkgs; [
              bashInteractive
              coreutils
              nix
              cacert
              shadow
              util-linux
            ];

            # Remove any duplicated packags
            uniquePackages = pkgs.lib.unique (minimal_packages ++ extraContents);

            # Try to ensure priorities are unique by applying a scale factor and index set during build.
            preBakedProfileManifest = let
              scale = builtins.length uniquePackages + 1;
              elements = pkgs.lib.imap0 (i: pkg:
                let
                  outputsToInstall = pkg.meta.outputsToInstall or (if pkg ? outputs then pkg.outputs else [ "out" ]);
                  allStorePaths = if pkg ? outputs
                                  then map (outName: "${pkg.${outName}}") outputsToInstall
                                  else [ "${pkg}" ];

                  # Extract the initial URL string safely
                  rawUrl = if (pkg ? src && pkg.src ? urls) then (builtins.elemAt pkg.src.urls 0) else "";

                  # Clean it up: if it uses 'mirror://', scrub it or point it to the global cache
                  cleanUrl = if builtins.substring 0 9 rawUrl == "mirror://"
                             then "" # Or replace with "https://tarballs.nixos.org" if you want a fallback mirror
                             else rawUrl;

                in {
                  name = "${pkg.pname or pkg.name}";
                  value = {
                    active = true;
                    priority = (pkg.meta.priority or 5) * scale + i;
                    outputs = outputsToInstall;
                    originalUrl = "flake:nixpkgs";

                    # Use our sanitized web URL string here
                    url = cleanUrl;

                    attrPath = "legacyPackages.x86_64-linux.${pkg.pname or pkg.name}";
                    storePaths = allStorePaths;
                  };
                }) uniquePackages;
            in
              pkgs.writeTextDir "root/.local/state/nix/profiles/profile/manifest.json" (builtins.toJSON {
                version = 3;
                elements = builtins.listToAttrs elements;
              });

            profileSymlink = pkgs.runCommand "profile-symlink" {} ''
              mkdir -p $out/root
              # Point the legacy standard user profile link directly to our state directory
              ln -s /.local/state/nix/profiles/profile $out/root/.nix-profile
            '';

          in
            pkgs.dockerTools.buildLayeredImage {
              name = name;
              tag = "latest";
              includeNixDB = true;

              uid = 1000;
              gid = 1000;

              # minimal set of packages needed for the scripts within this flake to work.
              contents = pkgs.lib.unique (uniquePackages ++ [
                (pkgs.writeTextDir "etc/nix/nix.conf" ''
                  experimental-features = nix-command flakes
                  substituters = https://cache.nixos.org/
                  trusted-users = root nixuser
                  sandbox = false
                  build-users-group =
                  ssl-cert-file = ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
                  require-sigs = false
                '')

                (pkgs.writeTextDir "etc/passwd" ''
                  root:x:0:0::/root:/bin/bash
                  nixuser:x:1000:1000::/home/nixuser:/bin/bash
                '')

                (pkgs.writeTextDir "etc/group" ''
                  root:x:0:
                  nixuser:x:1000:
                  nixbld:x:30000:1000
                '')

                (pkgs.writeTextDir "root/.bashrc" "")

                (pkgs.runCommand "create-dirs" {} ''
                  mkdir -p $out/nix/store/.links
                  mkdir -p $out/nix/var/nix/{db,profiles,gcroots,temproots,userpool}
                  mkdir -p $out/nix/var/nix/profiles/per-user/1000
                '')

                (pkgs.writeScriptBin "setup-permissions" ''
                  #!/bin/bash
                  set -euo pipefail
                  mkdir -p /nix/store/.links
                  mkdir -p /nix/var/nix/{db,profiles,gcroots,temproots,userpool}
                  mkdir -p /nix/var/nix/profiles/per-user/1000
                  # Don't recurse, as docker duplicates files on chmod (even when identical).
                  chown 1000:1000 /nix/store/
                  chmod 755 /nix/store/
                  chown -R 1000:1000 /nix/var/
                  chmod -R 755 /nix/var/
                  mkdir -p /home/nixuser/.local/state /home/nixuser/.cache
                  echo "" > /home/nixuser/.bashrc
                  chown -R 1000:1000 /home/nixuser
                  chmod -R 755 /home/nixuser
                '')

                (pkgs.writeScriptBin "copy-nix-profile-manifest" ''
                  PROFILES_DIR="/home/nixuser/.local/state/nix/profiles"
                  PROFILE_DIR="$PROFILES_DIR/profile"

                  mkdir -p "$PROFILES_DIR"
                  chown -R 1000:1000 /home/nixuser/.local/
                  ln -sf "$PROFILE_DIR" "/home/nixuser/.nix-profile" 2>/dev/null || true
                  # 'profile' needs to be a link, not a directory 
                  echo ln -sf /root/.local/state/nix/profiles/profile "$PROFILE_DIR"
                  ln -s /root/.local/state/nix/profiles/profile "$PROFILE_DIR"
                '')

                (pkgs.writeScriptBin "populate-nix-profile-manifest" ''
                  #!/bin/bash
                  set -euo pipefail
                  
                  PROFILE_DIR="$HOME/.local/state/nix/profiles/profile"
                  MANIFEST="$PROFILE_DIR/manifest.json"
                  
                  mkdir -p "$PROFILE_DIR"
                  chmod u+w "$MANIFEST" 2>/dev/null || true
                  ln -sf "$PROFILE_DIR" "$HOME/.nix-profile" 2>/dev/null || true
                  
                  json=$(readlink -f /bin/* 2>/dev/null \
                    | grep -o '^/nix/store/[^/]*' \
                    | sort -u \
                    | while IFS= read -r p; do
                        n="''${p##*/}"; n="''${n#*-}"
                        printf '"%s":{"active":true,"priority":5,"storePaths":["%s"]}\n' "$n" "$p"
                      done | paste -sd, -)
                  
                  echo "{\"version\":3,\"elements\":{''${json:-}}}" > "$MANIFEST"
                '')

                (pkgs.writeScriptBin "init-container" ''
                  #!/bin/bash
                  /bin/setup-permissions
                '')

                (pkgs.writeScriptBin "entrypoint" ''
                  #!/bin/bash
                  /bin/setup-permissions
                  #/bin/populate-nix-profile-manifest
                  /bin/copy-nix-profile-manifest
                  cd /home/nixuser
                  if [ $# -eq 0 ]; then
                    exec setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/nixuser USER=nixuser NIX_REMOTE= bash
                  else
                    exec setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/nixuser USER=nixuser NIX_REMOTE= "$@"
                  fi
                '')
              ]) ++ [ preBakedProfileManifest profileSymlink ];

              config = {
                WorkingDir = "/home/nixuser";
                Entrypoint = [ entrypoint ];
                Env = [
                  "HOME=/tmp"
                  "USER=nixuser"
                  "PATH=/bin:/usr/bin:/home/nixuser/.nix-profile/bin"
                  "TMPDIR=/home/nixuser/.cache"
                  "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  "NIX_REMOTE_TRUSTED_PUBLIC_KEYS=cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                  "NIX_REMOTE="
                  "UMASK=022"
                  "NIX_PATH=nixpkgs=flake:nixpkgs"
                ];
              } // extraConfig ;
            };

        images = basePkgs.lib.mapAttrs buildLayeredImage baseSpecs.image_specs;
        runScripts = basePkgs.lib.mapAttrs runScript images;

      in {
        packages = images // runScripts;
      };
    in {
      lib.buildImages = buildImages;
    };
}

