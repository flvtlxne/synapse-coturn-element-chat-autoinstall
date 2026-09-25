#!/usr/bin/env bash
# Interactive Matrix account creation for the existing Synapse container.
set -euo pipefail

CONTAINER="${MATRIX_CONTAINER:-matrix_synapse}"
CONFIG="${MATRIX_CONFIG:-/data/homeserver.yaml}"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

trap 'printf "\nExiting.\n" >&2; exit 130' INT

[[ -t 0 && -t 1 ]] || fail 'Run this script in an interactive SSH terminal.'
command -v docker >/dev/null 2>&1 || fail 'Docker is not installed.'
docker info >/dev/null 2>&1 || fail 'Docker is not accessible. Check the Docker service and the current user permissions.'

running=$(docker inspect --type container --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null) ||
    fail "Container $CONTAINER was not found. Run docker compose up -d in the project directory first."
[[ "$running" == true ]] || fail "Container $CONTAINER is stopped. Start the Synapse service first."

printf '\nChecking Synapse configuration and readiness (up to 60 seconds)...\n'
if ! docker exec -i "$CONTAINER" python - "$CONFIG" <<'PY'
import pathlib
import sys
import time
import urllib.error
import urllib.request
import yaml

def stop(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        config = yaml.safe_load(stream)
except (OSError, UnicodeError, yaml.YAMLError):
    stop("Could not read homeserver.yaml. Check the path, permissions, and YAML syntax.")
if not isinstance(config, dict):
    stop("homeserver.yaml must contain a Synapse configuration mapping.")

secret = config.get("registration_shared_secret")
secret_path = config.get("registration_shared_secret_path")
if secret and secret_path:
    stop("Both shared secret settings are configured; only one must be set.")
if secret_path and not secret:
    try:
        secret = pathlib.Path(secret_path).read_text(encoding="utf-8").strip()
    except (OSError, TypeError, UnicodeError):
        stop("Could not read the file specified by registration_shared_secret_path.")
if not isinstance(secret, str) or not secret:
    stop("Registration requires registration_shared_secret or registration_shared_secret_path.")
del secret

# Match the HTTP client listener used by register_new_matrix_user.
url = "http://localhost:8008"
for listener in config.get("listeners", []):
    is_client = any("client" in resource.get("names", [])
                    for resource in listener.get("resources", []))
    if listener.get("type") == "http" and not listener.get("tls", False) and is_client:
        url = "http://localhost:" + str(listener["port"])
        break

deadline = time.monotonic() + 60
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
while time.monotonic() < deadline:
    timeout = min(3, max(0.1, deadline - time.monotonic()))
    try:
        with opener.open(url + "/_matrix/client/versions", timeout=timeout) as response:
            if response.status == 200:
                break
    except (urllib.error.URLError, OSError):
        pass
    time.sleep(min(2, max(0, deadline - time.monotonic())))
else:
    stop("Synapse did not respond within 60 seconds. Check the container status and logs.")
PY
then
    fail 'Synapse checks failed. No account creation was attempted.'
fi

printf '\nMatrix user registration\n'
printf 'Enter a username without @ or the domain, then enter the password twice.\n'
printf 'Make admin [no]: type yes for an administrator, or press Enter for a regular user.\n'
printf 'Choose yes when creating the first administrator account.\n\n'

while true; do
    if docker exec -it "$CONTAINER" register_new_matrix_user -c "$CONFIG"; then
        printf '\nAccount created successfully.\n'
    else
        status=$?
        printf '\nRegistration failed (exit code %s). See the message above.\n' "$status" >&2
        exit "$status"
    fi

    while true; do
        if ! read -r -p 'Create another user? [y/N]: ' answer; then
            printf '\n'
            exit 0
        fi
        case "$answer" in
            y|Y|yes|YES) break ;;
            ''|n|N|no|NO) exit 0 ;;
            *) printf 'Please answer y or n.\n' ;;
        esac
    done
done
