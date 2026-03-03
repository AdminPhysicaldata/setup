#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMÈTRES OBLIGATOIRES
# =========================
IFACE="enp1s0"                 # interface réseau (ip link)
STATIC_IP_CIDR="192.168.1.50/24"
GATEWAY="192.168.1.1"
DNS1="1.1.1.1"
DNS2="8.8.8.8"

# =========================
# OUTILS
# =========================
log() { printf "[%s] %s\n" "$(date +%F\ %T)" "$*"; }
die() { printf "[ERR] %s\n" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Lancer en root: sudo $0"
}

check_iface() {
  ip link show "$IFACE" >/dev/null 2>&1 || die "Interface introuvable: $IFACE"
}

# =========================
# IP STATIQUE
# =========================
configure_static_ip_nmcli() {
  log "NetworkManager détecté -> config IP statique via nmcli"

  # Trouver la connexion associée à l'interface
  local con
  con="$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')"
  [[ -n "${con:-}" ]] || die "Aucune connexion NetworkManager pour $IFACE"

  nmcli con mod "$con" ipv4.method manual
  nmcli con mod "$con" ipv4.addresses "$STATIC_IP_CIDR"
  nmcli con mod "$con" ipv4.gateway "$GATEWAY"
  nmcli con mod "$con" ipv4.dns "$DNS1 $DNS2"
  nmcli con mod "$con" ipv6.method ignore

  nmcli con down "$con" || true
  nmcli con up "$con"

  log "IP statique appliquée via NetworkManager sur $IFACE"
}

configure_static_ip_systemd_networkd() {
  log "systemd-networkd détecté -> config IP statique via systemd-networkd"

  mkdir -p /etc/systemd/network
  cat >"/etc/systemd/network/10-${IFACE}.network" <<EOF
[Match]
Name=${IFACE}

[Network]
Address=${STATIC_IP_CIDR}
Gateway=${GATEWAY}
DNS=${DNS1}
DNS=${DNS2}
EOF

  systemctl enable --now systemd-networkd
  systemctl disable --now NetworkManager 2>/dev/null || true

  # Resolver
  systemctl enable --now systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true

  systemctl restart systemd-networkd systemd-resolved

  log "IP statique appliquée via systemd-networkd sur $IFACE"
}

configure_static_ip() {
  check_iface

  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    command -v nmcli >/dev/null 2>&1 || die "nmcli manquant alors que NetworkManager est actif"
    configure_static_ip_nmcli
    return
  fi

  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    configure_static_ip_systemd_networkd
    return
  fi

  # Fallback: activer systemd-networkd si aucun gestionnaire clair
  configure_static_ip_systemd_networkd
}

# =========================
# DOCKER (OFFICIEL)
# =========================
install_docker() {
  log "Installation Docker Engine (repo officiel)"

  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename arch
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  arch="$(dpkg --print-architecture)"

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${codename} stable
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker

  log "Docker installé"
  docker --version || true
}

# =========================
# MAIN
# =========================
main() {
  require_root

  # 1) IP statique
  configure_static_ip

  # 2) Docker
  install_docker

  log "Vérification réseau:"
  ip -br addr show "$IFACE" || true
  ip route || true

  log "Test docker:"
  docker run --rm hello-world >/dev/null 2>&1 && log "hello-world OK" || log "hello-world FAIL"
}

main "$@"
