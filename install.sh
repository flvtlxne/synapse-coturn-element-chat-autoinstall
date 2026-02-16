#!/usr/bin/env bash
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

# ================= Swap size =================

SWAP_SIZE="3G"

msg() {
	echo -e "\n=== $1 ==="
}

# ================= Sudo requirements =================

require_root_or_sudo() {
	if [[ "$EUID" -ne 0 ]]; then
		if ! command -v sudo >/dev/null 2>&1; then
			echo "sudo is required but not installed."
			exit 1
		fi
	fi
}

RUNTIME_USER="${SUDO_USER:-$USER}"

if [[ "$RUNTIME_USER" == "root" ]]; then
	echo "WARNING:"
	echo "Do not run docker compose commands as root!"
	echo "Installation can be run as root, but containers must be started as a normal user."
fi

echo "Runtime user: $RUNTIME_USER"

# ================= OS Release =================

detect_os() {
	source /etc/os-release

	case "$ID" in
		ubuntu|debian)
			DISTR="$ID"
			CODENAME="$VERSION_CODENAME"
			;;
		*)
			echo "Unsupported OS: $ID"
			exit 1
			;;
	esac

	echo "Detected OS: $PRETTY_NAME"
}

# ================= Updates =================

system_update () {
	msg "System update"
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt autoremove -y
	sudo apt clean -y
}

# ================= Docker checks =================

docker_installed() {
	command -v docker >/dev/null 2>&1
}

docker_running() {
	if docker info >/dev/null 2>&1; then
		return 0
	fi

	if command -v sudo >/dev/null 2>&1; then
		sudo docker info >/dev/null 2>&1
		return $?
	fi

	return 1
}

docker_compose_installed() {
	if docker compose version --short >/dev/null 2>&1; then
		return 0
	fi

	if command -v sudo >/dev/null 2>&1; then
		sudo docker compose version --short >/dev/null 2>&1
		return $?
	fi

	return 1
}

docker_group_exists() {
	getent group docker >/dev/null 2>&1
}

ensure_docker_group() {
	if ! getent group docker >/dev/null 2>&1; then
		echo "Creating docker group..."
		sudo groupadd docker
	fi

	if ! id -nG "$RUNTIME_USER" | grep -qw docker; then
		echo "Adding $RUNTIME_USER to docker group..."
		sudo usermod -aG docker "$RUNTIME_USER"
		echo
		echo "Docker group was updated."
		echo "You must log out and log in again before continuing."
		echo
		echo "Then run:"
		echo "	docker compose up -d"
		exit 0
	fi
		
	echo "User $RUNTIME_USER already in docker group."
}

check_existing_docker() {
	if docker_installed; then
		msg "Docker detected."

		ensure_docker_group

		if docker_running; then
			echo "Docker daemon is running."

			if docker_compose_installed; then
				echo "Docker Compose plugin detected."
			else
				echo "WARNING: Docker Compose plugin not found!"
			fi

			read -rp "Skip Docker installation? [y/N]: " ans
			case "$ans" in
				n|N)
					SKIP_DOCKER_INSTALL="false"
					;;
				*)
					SKIP_DOCKER_INSTALL="true"
					;;
			esac
			return
		else
			echo
			echo "ERROR: Docker daemon is not accessible."
			echo "This may be caused by:"
			echo "	- Docker not running;"
			echo "	- Current user not in docker group;"
			echo "	- Insufficient permissions to /var/run/docker.sock"
			exit 1
		fi
	fi

	SKIP_DOCKER_INSTALL="false"
}

# ================= Docker =================

install_docker() {
	if [[ "${SKIP_DOCKER_INSTALL:-false}" == "true" ]]; then
		msg "Skipping Docker installation"
		return
	fi

	msg "Installing Docker"

	sudo apt install -y \
		ca-certificates \
		curl \
		gnupg \
		lsb-release

	sudo mkdir -p /etc/apt/keyrings

	curl -fsSL "https://download.docker.com/linux/$DISTR/gpg" | \
		sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
		https://download.docker.com/linux/$DISTR \
		$CODENAME stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

	sudo apt update -y

	sudo apt install -y \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-compose-plugin

	sudo systemctl enable docker
	sudo systemctl start docker

	sudo usermod -aG docker "$RUNTIME_USER"

	echo
	echo "Docker installed and user added to docker group."
	echo "Please log out and log in again, then run:"
	echo "	docker compose up -d"
	exit 0
}

# ================= Swap =================

setup_swap() {
	msg "Configuring swap ($SWAP_SIZE)"

	if free | awk '/Swap:/ {exit !$2}'; then
		echo "Swap already exists, skipping."
		return
	fi

	sudo fallocate -l "$SWAP_SIZE" /swapfile
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile
	sudo swapon /swapfile

	echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
	echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

	sudo sysctl vm.swappiness=10
}

# ================= Checking project directories =================

confirm_dir() {
	local dir="$1"

	if [[ -d "$dir" ]]; then
		read -rp "Directory '$dir' already exists. Recreate it? [y/N]: " ans
		case "$ans" in
			y|Y)
				rm -rf "$dir"
				mkdir -p "$dir"
				;;
			*)
				echo "Keeping existing directory: $dir"
				;;
		esac
	else
		mkdir -p "$dir"
	fi 
}

# ================= Preparing project directories =================

prepare_dirs() {
	msg "Preparing project directories"
	confirm_dir synapse
	confirm_dir postgres
	confirm_dir element
	confirm_dir turn
	confirm_dir traefik
	confirm_dir traefik/dynamic
}

# ================= Validation =================
validate_env() {
	if [[ "$TLS_ENABLED" == "true" ]]; then
		: "${FULL_DOMAIN:?FULL_DOMAIN is required when TLS is enabled}"
		: "${CERT_PATH:?CERT_PATH is required when TLS is enabled}"
	fi
}

# ================= Interactive env setup =================

setup_env_interactive() {
	msg "Interactive env configuration"

	# ---------- Domain ----------
	echo
	echo "Domain configuration"

	read -rp "FULL_DOMAIN (e.g. matrix.example.com): " FULL_DOMAIN
	[[ -n "$FULL_DOMAIN" ]] || {
		echo "FULL_DOMAIN cannot be empty"
		exit 1
	}

	TLS_ENABLED="true"
	CERT_PATH="/letsencrypt/acme.json"

	# ---------- PostgreSQL ----------
	echo
	echo "PostgreSQL configuration"

	read -rp "POSTGRES_DATABASE [synapse]: " input
	POSTGRES_DATABASE="${input:-synapse}"

	read -rp "POSTGRES_USER [synapse]: " input
	POSTGRES_USER="${input:-synapse}"

	read -rsp "POSTGRES_PASSWORD: " POSTGRES_PASSWORD
	echo
	[[ -n "$POSTGRES_PASSWORD" ]] || {
		echo "POSTGRES_PASSWORD cannot be empty!"
		exit 1
	}

	# ---------- TURN ----------
	echo
	echo "TURN configuration"

	read -rsp "TURN_RANDOM_SECRET (leave this field empty to auto-generate): " input
	echo
	if [[ -z "$input" ]]; then
		TURN_RANDOM_SECRET="$(openssl rand -hex 32)"
		echo "Generated TURN_RANDOM_SECRET"
	else
		TURN_RANDOM_SECRET="$input"
	fi

	# ---------- PGAdmin ----------
	echo
	echo "PGAdmin configuration"

	read -rp "PGADMIN_PREFIX (URL path) [pgadmin]: " input
	PGADMIN_PREFIX="${input:-pgadmin}"

	read -rp "PGADMIN_DEFAULT_EMAIL [admin@$FULL_DOMAIN]: " input
	PGADMIN_DEFAULT_EMAIL="${input:-admin@$FULL_DOMAIN}"

	read -rsp "PGADMIN_DEFAULT_PASSWORD: " PGADMIN_DEFAULT_PASSWORD
	echo
	[[ -n "$PGADMIN_DEFAULT_PASSWORD" ]] || {
		echo "PGADMIN_DEFAULT_PASSWORD cannot be empty"
		exit 1
	}

	# ---------- Grafana ----------
	echo
	echo "Grafana configuration"

	read -rp "GRAFANA_PATH_PREFIX [grafana]: " input
	GRAFANA_PATH_PREFIX="${input:-grafana}"

	read -rp "GRAFANA_USER [admin]: " input
	GRAFANA_USER="${input:-admin}"

	read -rsp "GRAFANA_PASSWORD: " GRAFANA_PASSWORD
	echo
	[[ -n "$GRAFANA_PASSWORD" ]] || {
		echo "GRAFANA_PASSWORD cannot be empty"
		exit 1
	}

	# ---------- Prometheus ----------
	echo
	echo "Prometheus configuration"
	read -rp "PROMETHEUS_PREFIX [prometheus]: " input
	PROMETHEUS_PREFIX="${input:-prometheus}"
	PROMETHEUS_EXTERNAL_URL="https://${FULL_DOMAIN}/${PROMETHEUS_PREFIX}"

	# ---------- Export ----------
	export \
		FULL_DOMAIN CERT_PATH TLS_ENABLED \
		POSTGRES_DATABASE POSTGRES_USER POSTGRES_PASSWORD \
		TURN_RANDOM_SECRET \
		PGADMIN_PREFIX PGADMIN_DEFAULT_EMAIL PGADMIN_DEFAULT_PASSWORD \
		GRAFANA_PATH_PREFIX GRAFANA_USER GRAFANA_PASSWORD \
		PROMETHEUS_PREFIX PROMETHEUS_EXTERNAL_URL

}

# ================= Rendering templates =================

render_templates() {
	msg "Rendering configuration templates"

	envsubst < templates/docker-compose.yml.tpl > docker-compose.yml
	envsubst < templates/env.tpl > .env
	envsubst < templates/element.config.json.tpl > element/config.json
	envsubst < templates/synapse.homeserver.yaml.tpl > synapse/homeserver.yaml
	envsubst < templates/synapse.log.config.tpl > synapse/localhost.log.config
	envsubst < templates/turnserver.conf.tpl > turn/turnserver.conf
	envsubst < templates/traefik.yml.tpl > traefik/traefik.yml
	envsubst < templates/acme.json.tpl > traefik/acme.json
	envsubst < templates/prometheus.yml.tpl > prometheus.yml
	envsubst < backup/env.tpl > backup/.env
	envsubst < traefik/dynamic/auth.yml.tpl > traefik/dynamic/auth.yml
	envsubst < traefik/dynamic/dashboard.yml.tpl > traefik/dynamic/dashboard.yml
	envsubst < traefik/dynamic/matrix-wellknown.yml.tpl > traefik/dynamic/matrix-wellknown.yml
}

require_root_or_sudo
detect_os
system_update
check_existing_docker
install_docker
setup_swap
prepare_dirs
setup_env_interactive
validate_env
render_templates

msg "Preparing ownership for runtime user"

sudo chown -R "$RUNTIME_USER:$RUNTIME_USER" \
	postgres element turn traefik \
	.env docker-compose.yml 2>/dev/null || true

msg "Fixing permissions for Synapse directory"
sudo chown -R 991:991 synapse
sudo chmod 750 synapse
msg "Setting permissions for acme.json"
sudo chmod 600 traefik/acme.json


# ================= End of script execution =================

msg "Installation completed successfully!"
echo
echo "Summary:"
echo "  TLS enabled: true (Let's Encrypt)"
echo "  Domain:      $FULL_DOMAIN"
echo "  Cert path:   $CERT_PATH"
echo
echo "IMPORTANT:"
echo "	- Installation was with root privileges."
echo "	- Docker containers must be started as user: $RUNTIME_USER."
echo
echo "Log out and log in again to apply docker group:"
echo "	su - $RUNTIME_USER"
echo
echo "Please edit .env and configuration files before running containers!"
echo
echo "After editing the configuration files, please run the command docker compose up -d"