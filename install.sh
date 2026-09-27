#!/usr/bin/env bash
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

# ================= Settings =================

SWAP_SIZE="3G"
TURN_MIN_PORT="49160"
TURN_MAX_PORT="49200"

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

# ================= Public IP detection =================

detect_public_ip() {
	local ip=""

	ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -n1)"

	if [[ -z "$ip" ]]; then
		ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
	fi

	printf '%s' "$ip"
}

# ================= Updates =================

system_update() {
	msg "System update"
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt autoremove -y
	sudo apt clean -y
}

# ================= Required utilities =================

install_required_utils() {
	msg "Installing required utilities"

	sudo apt install -y \
		curl \
		gettext-base \
		openssl
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
		echo "You must log out and log in again, then run ./install.sh again."
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

			read -rp "Skip Docker installation? [Y/n]: " ans
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
			echo "  - Docker not running;"
			echo "  - Current user not in docker group;"
			echo "  - Insufficient permissions to /var/run/docker.sock"
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
		sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

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
	echo "Please log out and log in again, then run ./install.sh again."
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
	mkdir -p traefik
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

	# ---------- Public IP ----------
	echo
	echo "Public IP configuration"

	DETECTED_IP="$(detect_public_ip)"

	if [[ -n "$DETECTED_IP" ]]; then
		read -rp "PUBLIC_IP_ADDR [$DETECTED_IP]: " input
		PUBLIC_IP_ADDR="${input:-$DETECTED_IP}"
	else
		read -rp "PUBLIC_IP_ADDR (autodetect failed): " PUBLIC_IP_ADDR
	fi

	[[ -n "$PUBLIC_IP_ADDR" ]] || {
		echo "PUBLIC_IP_ADDR cannot be empty"
		exit 1
	}

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
	echo "PGAdmin configuration (available only via SSH tunnel on 127.0.0.1:5050)"

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
	echo "Grafana configuration (available only via SSH tunnel on 127.0.0.1:3000)"

	read -rp "GRAFANA_USER [admin]: " input
	GRAFANA_USER="${input:-admin}"

	read -rsp "GRAFANA_PASSWORD: " GRAFANA_PASSWORD
	echo
	[[ -n "$GRAFANA_PASSWORD" ]] || {
		echo "GRAFANA_PASSWORD cannot be empty"
		exit 1
	}

	# ---------- Export ----------
	export \
		PUBLIC_IP_ADDR \
		FULL_DOMAIN CERT_PATH TLS_ENABLED \
		POSTGRES_DATABASE POSTGRES_USER POSTGRES_PASSWORD \
		TURN_RANDOM_SECRET TURN_MIN_PORT TURN_MAX_PORT \
		PGADMIN_DEFAULT_EMAIL PGADMIN_DEFAULT_PASSWORD \
		GRAFANA_USER GRAFANA_PASSWORD
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
	envsubst < traefik/templates/matrix-wellknown.yml.tpl > traefik/dynamic/matrix-wellknown.yml
}

# ================= Firewall =================

open_firewall_ports() {
	msg "Configuring firewall (ufw)"

	if ! sudo ufw status 2>/dev/null | grep -q "Status: active"; then
		echo "ufw is not installed or not active, skipping."
		echo "If you use another firewall, open: 80/tcp, 443/tcp, 3478/tcp+udp, ${TURN_MIN_PORT}-${TURN_MAX_PORT}/udp"
		return
	fi

	sudo ufw allow 80/tcp
	sudo ufw allow 443/tcp
	sudo ufw allow 3478/tcp
	sudo ufw allow 3478/udp
	sudo ufw allow "${TURN_MIN_PORT}:${TURN_MAX_PORT}/udp"
}

# ================= Main =================

require_root_or_sudo
detect_os
system_update
install_required_utils
check_existing_docker
install_docker
setup_swap
prepare_dirs
setup_env_interactive
validate_env
render_templates
open_firewall_ports

msg "Preparing ownership for runtime user"

sudo chown -R "$RUNTIME_USER:$RUNTIME_USER" \
	postgres element turn traefik grafana \
	.env docker-compose.yml prometheus.yml 2>/dev/null || true

msg "Fixing permissions for Synapse directory"
sudo chown -R 991:991 synapse
sudo chmod 750 synapse

msg "Setting permissions for acme.json"
sudo chmod 600 traefik/acme.json

msg "Restricting permissions for secrets"
sudo chmod 600 .env backup/.env 2>/dev/null || true
sudo chmod 600 turn/turnserver.conf

# ================= End of script execution =================

msg "Installation completed successfully!"
echo
echo "Summary:"
echo "  Domain:      $FULL_DOMAIN"
echo "  Public IP:   $PUBLIC_IP_ADDR"
echo "  TURN ports:  3478/tcp+udp, ${TURN_MIN_PORT}-${TURN_MAX_PORT}/udp"
echo
echo "Admin panels (only via SSH tunnel, not exposed to the internet):"
echo "  Grafana:           http://localhost:3000"
echo "  Prometheus:        http://localhost:9090"
echo "  pgAdmin:           http://localhost:5050"
echo "  Traefik dashboard: http://localhost:8080/dashboard/"
echo
echo "Containers must be started as user: $RUNTIME_USER"
echo "Next step: docker compose up -d"