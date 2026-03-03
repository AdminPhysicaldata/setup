#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/AdminPhysicaldata/server"
DEST_DIR="/opt/server"

log() { printf "[%s] %s\n" "$(date +%F\ %T)" "$*"; }
die() { printf "[ERR] %s\n" "$*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Lancer en root: sudo $0"

log "Installation dépendances"
apt-get update
apt-get install -y ca-certificates curl gnupg git

log "Ajout clé + dépôt Docker (officiel)"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable
EOF

log "Installation Docker Engine + Compose"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Activation service Docker"
systemctl enable --now docker

log "Test Docker"
docker run --rm hello-world >/dev/null 2>&1 && log "hello-world OK" || log "hello-world FAIL"

log "Clone du repo"
mkdir -p "$(dirname "$DEST_DIR")"
if [[ -d "$DEST_DIR/.git" ]]; then
  log "Repo déjà présent -> git pull"
  git -C "$DEST_DIR" pull --rebase
else
  git clone "$REPO_URL" "$DEST_DIR"
fi

log "Terminé: Docker installé, repo dans $DEST_DIR"




deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
