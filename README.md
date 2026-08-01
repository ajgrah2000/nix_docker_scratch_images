Nix docker scratch images
=========================

nix to build clean/fresh docker images that contain nix packages (on each invokation).

Goal:
  - Allow a clean docker contain that can include a local repository and nix declared packages.
  - Main use case, 'coding agents'.
  - Experiment with docker layers/reuse/nix

## Dependencies
 | Tool   | Purpose                             | Reference                               |
 | ----   | -------                             | ---------                               |
 | nix    | To create the images from the host. | https://nix.dev/install-nix.html        |
 | docker | To run the images.                  | https://docs.docker.com/engine/install/ |

### Setup 
    cd ./new_repo
    git init

    nix flake init --refresh -t "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git"

    chmod u+x ./nix_docker_from_scratch.sh

### Run:

    ./nix_docker_from_scratch.sh docker-nix-minimal

Run without any arguments to get the list of images (changeable by replacing 'image_configs.nix).  (posslby not stale) current options
'docker-nix-all','docker-nix-opencode','docker-nix-claude'

## Run without setup
    nix run --no-write-lock-file "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git#docker-nix-all"

    nix run --no-write-lock-file "git+ssh://git@github.com/ajgrah2000/nix_docker_scratch_images.git#docker-nix-all" -- -v $(pwd)/data:/data  
### Run via nix commands:
Directly via nix:
    nix run .#docker-nix-all
or 
    nix run <path_to_this_repo>#docker-nix-all

## Changing image packages
   - simple/replacement: [image_configs.nix](./examples/image_configs.nix.simple)
   - extend: [image_configs.nix](./examples/image_configs.nix.simple)

## Docker config/settings:
    Depending on desired reopsitory layout/setup, options can be provided to docker.
    eg '-v' options to dockerhow you want 

    nix run .#docker-nix-all -- -v $(pwd)/auth.json:/home/nixuser/.local/share/opencode/auth.json -v $(pwd)/data/opencode.json:/opencode.json -v $(pwd)/data:/data

# Structure
    flake.nix - Top level flake file.
                imports the 'image configs'.
                creates the run entry points.
                specifies which systems to build for.

    docker_nix/flake.nix - Declare how a single docker image is built and run.
                           
    image_configs.nix - Location do choose what images to create and packages they include.

## Example
Simple example, specifying 1 image, runnable via 'nix run .#docker-nix-simple'

image\_configs.nix:

    pkgs: rec {
      # Convinience lists of packages.
      base_dev = (with pkgs; [
        gnugrep
      ]);
      image_specs = {
        docker-nix-simple = {
          contents = base_dev;
          config = { 
            # Overriding 'pkgs.dockerTools.buildLayeredImage' config options for this image
            allowUnfree = true;
          };
        };
      };
    }

# Known Issues
   'docker arguments'  Aren't super flexible:
       docker run "$@" --rm -it "$IMAGE_NAME"

       > nix run .#docker-nix-minimal -- <args>
       docker run <args> --rm -it "$IMAGE_NAME"

       The '--entrypoint' argument expects/requires: --entrypoint cmd IMG_NAME cmd_arg1 cmd_arg2
         Which can't (easily) be achieved the the expansion.

       Example:
         > nix run .#docker-nix-minimal -- echo docker-nix-minimal hello
         hello --rm --it docker-nix-minimal

       For most/many docker arguments it's ok.

# Profiling/performance.
    IMAGE_NAME=docker-nix-all:latest
    
    time docker run --rm --entrypoint sh ${IMAGE_NAME} -c 'echo container-started'
    time docker run --rm ${IMAGE_NAME}
    
    docker inspect ${IMAGE_NAME} --format='Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
    
    time /bin/entrypoint

# Trouble shooting
    # If nix appears to be using a 'stale' repositories (hasn't picked up github changes that have been pushed to this repository).
    # add '--refresh' to commands:
    nix flake show --refresh

# References
    Current iteration based on:
        https://github.com/grigio/docker-nixuser


