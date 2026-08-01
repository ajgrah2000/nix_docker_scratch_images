#!/bin/bash
# Example script.  Query the flake to get possible 'apps', then run it with arguments to docker.
# Definitely overkill (the entire script is just argument validation).
# This could be done by querying the '.nix' files directly, although this helps check end to end that they're available.

# Should match the 'flake.nix' file'
SYSTEMS=$(nix flake show --all-systems --json | jq -r ' .apps | keys[]')
IMAGES=$(nix flake show --all-systems --json | jq -r '.apps | paths | select(length == 2) | .[1]' | sort -u)
AUTH_JSON="$HOME/.local/share/opencode/auth.json"
OPENCODE_JSON="$(pwd)/data/opencode.json"

VALID_IMAGES=(${IMAGES})
VALID_SYSTEMS=(${SYSTEMS})

SYSTEM="x86_64-linux"
if [[ "${1:-}" == "--system" ]]; then
  SYSTEM="$2"
  shift 2
fi

usage() {
        echo "Usage: $0 --system {${VALID_SYSTEMS[*]}} {${VALID_IMAGES[*]}}"
    exit 1
}

# Require exactly one argument
[[ $# -ne 1 ]] && usage

IMAGE="$1"

# Check if the arguments are valid:
if [[ ! " ${VALID_IMAGES[*]} " =~ " ${IMAGE} " ]]; then
    echo "Error: invalid argument '${IMAGE}'"
    usage
fi

if [[ ! " ${VALID_SYSTEMS[*]} " =~ " ${SYSTEM} " ]]; then
    echo "Error: invalid --system argument: '${SYSTEM}'"
    usage
fi

SYSTEM_IMAGE=${SYSTEM}.${IMAGE}

# Add additional docker 'auth' options
DOCKER_OPTS=()

if [ -f "$AUTH_JSON" ]; then
  DOCKER_OPTS+=(-v "$AUTH_JSON:/home/nixuser/.local/share/opencode/auth.json")
else
  echo "Warning: '$AUTH_JSON' does not exist, opencode will run without authentication." >&2
fi

if [ -f "$OPENCODE_JSON" ]; then
  DOCKER_OPTS+=(-v "$OPENCODE_JSON:/opencode.json")
else
  echo "Warning: '$OPENCODE_JSON' does not exist, opencode will run without config." >&2
fi

# Show then run the resulting command (which can then be used as a single line for future runs, instead of this monstrous script).
COMMAND='nix run .#apps.${SYSTEM_IMAGE} -- "${DOCKER_OPTS[@]}" -v $(pwd)/data:/data'
eval echo "Running: ${COMMAND}"
eval "$COMMAND"
