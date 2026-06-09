#!/usr/bin/env bash
set -euo pipefail

OLLAMA_HOST_VALUE="${OLLAMA_HOST_VALUE:-0.0.0.0:11434}"
OLLAMA_SCHED_SPREAD_VALUE="${OLLAMA_SCHED_SPREAD_VALUE:-1}"
AUTO_REBOOT=0
SKIP_NVIDIA=0
FORCE_NVIDIA_580=0
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'USAGE'
Usage: install_ollama_lan.sh [options]

Installs/configures Ollama for LAN use:
  - Installs Ollama if missing
  - Keeps DHCP/local DNS untouched
  - Configures Ollama to listen on 0.0.0.0:11434
  - Enables OLLAMA_SCHED_SPREAD=1
  - Checks NVIDIA GPUs and repairs driver mismatch when needed

Options:
  --reboot             Reboot automatically if the NVIDIA driver was changed
  --no-spread          Do not set OLLAMA_SCHED_SPREAD=1
  --skip-nvidia        Do not inspect or install NVIDIA drivers
  --force-nvidia-580   Install NVIDIA driver branch 580 even if nvidia-smi works
  --host HOST:PORT     Ollama bind address, default 0.0.0.0:11434
  -h, --help           Show this help

Environment:
  OLLAMA_HOST_VALUE          Override bind address
  OLLAMA_SCHED_SPREAD_VALUE  Override spread value
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf '\nWARN: %s\n' "$*" >&2
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reboot)
      AUTO_REBOOT=1
      ;;
    --no-spread)
      OLLAMA_SCHED_SPREAD_VALUE=""
      ;;
    --skip-nvidia)
      SKIP_NVIDIA=1
      ;;
    --force-nvidia-580)
      FORCE_NVIDIA_580=1
      ;;
    --host)
      shift
      [ "$#" -gt 0 ] || die "--host needs HOST:PORT"
      OLLAMA_HOST_VALUE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

export DEBIAN_FRONTEND=noninteractive

apt_install() {
  apt-get update
  apt-get -y install "$@"
}

count_nvidia_pci_gpus() {
  lspci -nn 2>/dev/null | grep -Eci 'VGA|3D|Display' | xargs -r echo >/dev/null
  lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -Eci 'NVIDIA|10de' || true
}

count_nvidia_smi_gpus() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true
  else
    echo 0
  fi
}

has_legacy_pascal_gpu() {
  lspci -nn 2>/dev/null | grep -Eiq 'NVIDIA.*(GP10|GeForce GTX 10|GTX 1050|GTX 1060|GTX 1070|GTX 1080)'
}

install_nvidia_driver_if_needed() {
  [ "$SKIP_NVIDIA" -eq 0 ] || {
    log "Skipping NVIDIA driver checks"
    return 0
  }

  local pci_count smi_count driver_changed branch packages
  pci_count="$(count_nvidia_pci_gpus)"
  smi_count="$(count_nvidia_smi_gpus)"
  driver_changed=0

  if [ "$pci_count" -eq 0 ]; then
    log "No NVIDIA GPUs found by PCI"
    return 0
  fi

  log "NVIDIA GPUs found by PCI: $pci_count; visible to nvidia-smi: $smi_count"

  if [ "$FORCE_NVIDIA_580" -eq 1 ] || has_legacy_pascal_gpu; then
    branch="580"
    packages="nvidia-driver-580 nvidia-dkms-580"
  else
    branch="current"
    if apt-cache show cuda-drivers >/dev/null 2>&1; then
      packages="cuda-drivers"
    elif command -v ubuntu-drivers >/dev/null 2>&1; then
      packages="__ubuntu_drivers__"
    else
      packages="nvidia-driver-580 nvidia-dkms-580"
      branch="580 fallback"
    fi
  fi

  if [ "$FORCE_NVIDIA_580" -eq 1 ] || [ "$smi_count" -lt "$pci_count" ]; then
    log "Installing NVIDIA driver branch: $branch"
    if [ "$packages" = "__ubuntu_drivers__" ]; then
      apt-get update
      if ubuntu-drivers install --gpgpu 2>/dev/null; then
        log "Installed GPU-only driver via ubuntu-drivers --gpgpu"
      else
        local recommended
        recommended="$(ubuntu-drivers list 2>/dev/null | grep -E '^nvidia-driver-[0-9]+' | head -n1 | awk '{print $1}')"
        if [ -n "$recommended" ]; then
          apt-get -y install --no-install-recommends "$recommended"
        else
          apt_install nvidia-driver-580 nvidia-dkms-580
        fi
      fi
    elif [ -n "$packages" ]; then
      apt_install $packages
    fi
    driver_changed=1
  else
    log "NVIDIA driver already sees all PCI GPUs"
  fi

  if [ "$driver_changed" -eq 1 ]; then
    touch /run/ollama-lan-driver-changed
    warn "NVIDIA driver changed. A reboot is required before final GPU verification."
  fi
}

install_ollama_if_needed() {
  apt_install curl ca-certificates pciutils gnupg

  if command -v ollama >/dev/null 2>&1; then
    log "Ollama already installed: $(ollama --version 2>/dev/null || true)"
    return 0
  fi

  log "Installing Ollama from official installer"
  curl -fsSL https://ollama.com/install.sh | sh
}

configure_ollama_service() {
  log "Configuring Ollama systemd override"
  mkdir -p /etc/systemd/system/ollama.service.d

  {
    printf '[Service]\n'
    printf 'Environment="OLLAMA_HOST=%s"\n' "$OLLAMA_HOST_VALUE"
    if [ -n "$OLLAMA_SCHED_SPREAD_VALUE" ]; then
      printf 'Environment="OLLAMA_SCHED_SPREAD=%s"\n' "$OLLAMA_SCHED_SPREAD_VALUE"
    fi
  } > /etc/systemd/system/ollama.service.d/override.conf

  systemctl daemon-reload
  systemctl enable ollama
  systemctl restart ollama
}

check_dns_without_changing_it() {
  log "Checking DHCP/local DNS without changing resolver settings"
  resolvectl status 2>/dev/null | sed -n '1,80p' || true

  if getent hosts ollama.com >/dev/null; then
    log "DNS can resolve ollama.com"
  else
    warn "DNS cannot resolve ollama.com. Keeping local DNS as requested; pulls may fail until DNS is fixed."
  fi
}

final_status() {
  log "Final status"
  systemctl is-active ollama || true
  systemctl show ollama -p Environment || true
  ss -ltnp 2>/dev/null | grep 11434 || true
  curl -s --max-time 5 "http://127.0.0.1:11434/api/version" || true
  printf '\n'

  local lan_ip
  lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [ -n "$lan_ip" ]; then
    log "Direct curl examples"
    printf 'curl http://%s:11434/api/version\n' "$lan_ip"
    printf 'curl http://%s:11434/api/tags\n' "$lan_ip"
    printf "curl http://%s:11434/api/pull -d '{\"model\":\"llama3.2\"}'\n" "$lan_ip"
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -L || true
  fi

  if [ -e /run/ollama-lan-driver-changed ]; then
    if [ "$AUTO_REBOOT" -eq 1 ]; then
      log "Rebooting because NVIDIA driver changed"
      reboot
    else
      warn "Reboot required to load the new NVIDIA driver. Run: sudo reboot"
    fi
  fi
}

install_ollama_if_needed
install_nvidia_driver_if_needed
configure_ollama_service
check_dns_without_changing_it
final_status
