#!/usr/bin/env bash
set -Eeuo pipefail

readonly DOCKER_ENGINE_VERSION='5:29.7.2-1~ubuntu.24.04~noble'
readonly CONTAINERD_VERSION='2.3.4-1~ubuntu.24.04~noble'
readonly BUILDX_VERSION='0.36.1-1~ubuntu.24.04~noble'
readonly COMPOSE_VERSION='5.5.0-1~ubuntu.24.04~noble'
readonly TAILSCALE_VERSION='1.102.3'
readonly EXPECTED_OPERATOR='alejandro'
readonly EXPECTED_DOCKER_DAEMON_JSON='{
  "live-restore": true,
  "log-driver": "local",
  "log-opts": {
    "max-file": "5",
    "max-size": "20m"
  }
}'

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  sudo bash ops/firebat/bootstrap_container_host.sh [--login-server https://headscale.example]

Installs exact Docker Engine, Compose, and Tailscale packages on Ubuntu 24.04,
enables their services, and adds `alejandro` to the docker group. If a Headscale
URL is supplied, the script starts the interactive device-enrollment flow. It
does not accept or store an auth key.
EOF
}

login_server=''
while (($#)); do
  case "$1" in
    --login-server)
      (($# >= 2)) || die '--login-server requires a URL'
      login_server="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

((EUID == 0)) || die 'run this bootstrap through sudo'
[[ -z "${login_server}" || "${login_server}" =~ ^https://[A-Za-z0-9._:-]+/?$ ]] ||
  die 'Headscale login server must be an HTTPS origin without a path'

for command in curl dpkg gpg install systemctl; do
  require_command "${command}"
done
[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == 'ubuntu' && "${VERSION_ID:-}" == '24.04' && "${VERSION_CODENAME:-}" == 'noble' ]] ||
  die "this bootstrap targets Ubuntu 24.04 noble; found ${PRETTY_NAME:-unknown}"
[[ "$(dpkg --print-architecture)" == 'amd64' ]] || die 'this bootstrap is pinned for amd64 Firebat One'
id "${EXPECTED_OPERATOR}" >/dev/null 2>&1 || die "operator account does not exist: ${EXPECTED_OPERATOR}"

install -d -o root -g root -m 0755 /etc/apt/keyrings
curl --fail --silent --show-error --location \
  https://download.docker.com/linux/ubuntu/gpg \
  --output /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF

curl --fail --silent --show-error --location \
  https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
  --output /usr/share/keyrings/tailscale-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg
curl --fail --silent --show-error --location \
  https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
  --output /etc/apt/sources.list.d/tailscale.list
chmod 0644 /etc/apt/sources.list.d/tailscale.list

env DEBIAN_FRONTEND=noninteractive apt-get update
env DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
  "docker-ce=${DOCKER_ENGINE_VERSION}" \
  "docker-ce-cli=${DOCKER_ENGINE_VERSION}" \
  "containerd.io=${CONTAINERD_VERSION}" \
  "docker-buildx-plugin=${BUILDX_VERSION}" \
  "docker-compose-plugin=${COMPOSE_VERSION}" \
  "tailscale=${TAILSCALE_VERSION}"

apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin tailscale >/dev/null

if [[ -e /etc/docker/daemon.json ]]; then
  [[ -f /etc/docker/daemon.json && ! -L /etc/docker/daemon.json ]] ||
    die '/etc/docker/daemon.json is not a regular file'
  [[ "$(</etc/docker/daemon.json)" == "${EXPECTED_DOCKER_DAEMON_JSON}" ]] ||
    die 'existing /etc/docker/daemon.json differs from the reviewed MaCSad policy'
else
  install -d -o root -g root -m 0755 /etc/docker
  printf '%s\n' "${EXPECTED_DOCKER_DAEMON_JSON}" >/etc/docker/daemon.json
  chmod 0644 /etc/docker/daemon.json
fi

usermod -aG docker "${EXPECTED_OPERATOR}"
systemctl daemon-reload
systemctl enable --now containerd.service docker.service tailscaled.service
systemctl is-active --quiet containerd.service
systemctl is-active --quiet docker.service
systemctl is-active --quiet tailscaled.service

docker_version="$(docker version --format '{{.Server.Version}}')"
compose_version="$(docker compose version --short)"
tailscale_version="$(tailscale version | sed -n '1p')"
[[ "${docker_version}" == '29.7.2' ]] || die "unexpected Docker version: ${docker_version}"
[[ "${compose_version}" == '5.5.0' ]] || die "unexpected Compose version: ${compose_version}"
[[ "${tailscale_version}" == "${TAILSCALE_VERSION}" ]] ||
  die "unexpected Tailscale version: ${tailscale_version}"

if [[ -n "${login_server}" ]]; then
  tailscale up --login-server="${login_server%/}" --hostname=firebat-1
else
  printf 'Tailscale is installed but not enrolled. Run:\n' >&2
  printf '  sudo tailscale up --login-server=https://YOUR-HEADSCALE --hostname=firebat-1\n' >&2
fi

printf 'Docker %s, Compose %s, and Tailscale %s are installed and enabled.\n' \
  "${docker_version}" "${compose_version}" "${tailscale_version}"
printf 'Reconnect the alejandro SSH session before running Docker without sudo.\n'
