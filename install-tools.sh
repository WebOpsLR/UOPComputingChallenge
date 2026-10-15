#!/usr/bin/env bash
#
# install-tools.sh
#
# Installs Docker, Minikube, kubectl, Helm, and Terraform on Linux, macOS, and
# Windows (through WSL 2). Tools that are already installed are skipped.
#
# Usage:
#   Linux / WSL : sudo ./install-tools.sh
#   macOS       : ./install-tools.sh     (Homebrew won't run with sudo)
#
#   On Windows, open your WSL distro and run the Linux command.
#
# Platform notes:
#   - Linux: supports apt (Debian/Ubuntu), dnf (Fedora), and yum (RHEL/CentOS).
#     Other distros need manual installation.
#   - macOS: uses Homebrew. Docker is installed as Docker Desktop, so you still
#     have to start it from the GUI afterwards.
#   - WSL: Docker is not installed inside WSL. You install Docker Desktop on
#     Windows and turn on WSL integration. The script detects WSL and tells you
#     what to do instead of installing an engine that would conflict.

set -euo pipefail

# HELPERS

log()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) ARCH="amd64"; warn "Unknown architecture '$ARCH_RAW', defaulting to amd64." ;;
esac

OS="$(uname -s)"

# Directory this script lives in — this is the challenge folder, and where the
# Terraform config and Helm chart live. Used to clean up Windows artefacts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect Windows Subsystem for Linux. On WSL, Docker comes from Docker Desktop
# on Windows rather than being installed in the distro.
IS_WSL=false
if [ "$OS" = "Linux" ]; then
  if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null \
     || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null \
     || [ -n "${WSL_DISTRO_NAME:-}" ]; then
    IS_WSL=true
  fi
fi

# Detect Linux package manager
PKG=""
if [ "$OS" = "Linux" ]; then
  if have apt-get; then PKG="apt"
  elif have dnf;   then PKG="dnf"
  elif have yum;   then PKG="yum"
  else warn "No supported package manager (apt/dnf/yum) found."; fi
fi

SUDO=""

# Temp dir for the logs of parallel jobs; removed when the script exits.
LOGDIR="$(mktemp -d)"
cleanup() { rm -rf "$LOGDIR"; }
trap cleanup EXIT

# Run a check_* function in the background, sending its output to a log file so
# parallel jobs don't mix their messages together on screen.
# Usage: run_bg <name> <function>
declare -a BG_NAMES=()
declare -a BG_PIDS=()
declare -a BG_LOGS=()
run_bg() {
  local name="$1" fn="$2"
  local logf="$LOGDIR/$name.log"
  ( "$fn" ) >"$logf" 2>&1 &
  BG_NAMES+=("$name")
  BG_PIDS+=("$!")
  BG_LOGS+=("$logf")
}

# Wait for all background jobs to finish, then print their logs in order.
# Returns the number of jobs that failed.
wait_bg() {
  local failures=0 i
  for i in "${!BG_PIDS[@]}"; do
    if ! wait "${BG_PIDS[$i]}"; then
      failures=$((failures + 1))
    fi
  done
  for i in "${!BG_NAMES[@]}"; do
    printf '\033[1;36m----- %s -----\033[0m\n' "${BG_NAMES[$i]}"
    cat "${BG_LOGS[$i]}" 2>/dev/null || true
  done
  # Clear the arrays so they can be reused for another batch.
  BG_NAMES=(); BG_PIDS=(); BG_LOGS=()
  return "$failures"
}

# ROOT ENFORCEMENT

require_root() {
  # macOS uses Homebrew, which won't run as root, so only require root on Linux.
  if [ "$OS" = "Darwin" ]; then
    if [ "$(id -u)" -eq 0 ]; then
      err "On macOS do NOT run this script as root. Homebrew refuses to run as root."
      err "Re-run without sudo:  ./install-tools.sh"
      exit 1
    fi
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root on Linux/WSL."
    err "Re-run with sudo:  sudo ./install-tools.sh"
    exit 1
  fi
}

# WINDOWS ARTEFACT CLEANUP

# When files are downloaded on Windows (e.g. the challenge ZIP), Windows attaches
# a "mark of the web" as an NTFS alternate data stream. Copying those files into
# WSL flattens each stream into a real file named '<file>:Zone.Identifier'.
# Helm then tries to parse these as YAML templates and fails with
# "control characters are not allowed", breaking 'terraform apply'.
# Cloning with git avoids this; here we clean up the ZIP-download case so the
# Terraform/Helm steps don't hit it later.
clean_zone_identifier() {
  local found
  found="$(find "$SCRIPT_DIR" -type f -name '*:Zone.Identifier' 2>/dev/null || true)"
  if [ -n "$found" ]; then
    local count
    count="$(printf '%s\n' "$found" | grep -c . || true)"
    log "Removing $count Windows 'Zone.Identifier' file(s) that would break Helm..."
    find "$SCRIPT_DIR" -type f -name '*:Zone.Identifier' -delete 2>/dev/null || true
    ok "Cleaned up Windows download artefacts."
  fi
}

# PACKAGE MANAGER PREP

# Update apt's package list once up front so the parallel installers don't each
# run their own 'apt-get update'. Does nothing for dnf/yum.
apt_refreshed=false
prep_pkg_mgr() {
  case "$PKG" in
    apt)
      log "Refreshing apt package lists (once)..."
      export DEBIAN_FRONTEND=noninteractive
      $SUDO apt-get update
      $SUDO apt-get install -y ca-certificates curl gnupg
      apt_refreshed=true
      ;;
    dnf)
      $SUDO dnf -y install dnf-plugins-core curl || true
      ;;
    yum)
      $SUDO yum install -y yum-utils curl || true
      ;;
  esac
}

# DOCKER

install_docker_linux() {
  case "$PKG" in
    apt)
      log "Installing Docker via apt (convenience script)..."
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      $SUDO sh /tmp/get-docker.sh
      rm -f /tmp/get-docker.sh
      ;;
    dnf)
      log "Installing Docker via dnf..."
      $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      $SUDO dnf -y install docker-ce docker-ce-cli containerd.io
      ;;
    yum)
      log "Installing Docker via yum..."
      $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      $SUDO yum install -y docker-ce docker-ce-cli containerd.io
      ;;
    *)
      err "Cannot install Docker automatically on this distro. See https://docs.docker.com/engine/install/"
      return 1
      ;;
  esac

  log "Enabling and starting the Docker service..."
  $SUDO systemctl enable --now docker 2>/dev/null || warn "Could not enable docker via systemctl (non-systemd system?)."

  # Add the user who ran sudo to the 'docker' group so they can use docker
  # without sudo (takes effect after they log out and back in).
  local target_user="${SUDO_USER:-}"
  if [ -n "$target_user" ] && [ "$target_user" != "root" ] && getent group docker >/dev/null 2>&1; then
    $SUDO usermod -aG docker "$target_user" || true
    warn "Added '$target_user' to the 'docker' group. Log out and back in for it to take effect."
  fi
}

install_docker_mac() {
  log "Installing Docker Desktop via Homebrew cask..."
  brew install --cask docker
  warn "Docker Desktop installed. Launch it from Applications once to start the engine."
}

check_docker() {
  if have docker; then
    ok "Docker already installed: $(docker --version 2>/dev/null || echo 'version unknown')"
    return 0
  fi

  if [ "$IS_WSL" = true ]; then
    err "Docker was not found in this WSL distro."
    warn "Do NOT install Docker Engine inside WSL for this challenge."
    warn "Instead, on Windows:"
    warn "  1. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    warn "  2. Docker Desktop > Settings > General: enable 'Use the WSL 2 based engine'."
    warn "  3. Docker Desktop > Settings > Resources > WSL Integration:"
    warn "     enable integration for this distro (${WSL_DISTRO_NAME:-your distro})."
    warn "  4. Restart this WSL shell, then re-run this script."
    return 1
  fi

  log "Docker not found. Installing..."
  if [ "$OS" = "Darwin" ]; then install_docker_mac; else install_docker_linux; fi
  have docker && ok "Docker installed: $(docker --version 2>/dev/null || echo 'version unknown')"
}

# KUBECTL

install_kubectl_linux() {
  log "Installing kubectl (latest stable) for linux/$ARCH..."
  local ver
  ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLO "https://dl.k8s.io/release/${ver}/bin/linux/${ARCH}/kubectl"
  $SUDO install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
}

install_kubectl_mac() {
  log "Installing kubectl via Homebrew..."
  brew install kubectl
}

check_kubectl() {
  if have kubectl; then
    ok "kubectl already installed: $(kubectl version --client 2>/dev/null | head -n1 || echo 'version unknown')"
    return 0
  fi
  log "kubectl not found. Installing..."
  if [ "$OS" = "Darwin" ]; then install_kubectl_mac; else install_kubectl_linux; fi
  have kubectl && ok "kubectl installed: $(kubectl version --client 2>/dev/null | head -n1 || echo 'version unknown')"
}

# MINIKUBE

install_minikube_linux() {
  log "Installing Minikube for linux/$ARCH..."
  local tmp="/tmp/minikube-linux-${ARCH}"
  curl -fsSL -o "$tmp" "https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-${ARCH}"
  $SUDO install "$tmp" /usr/local/bin/minikube
  rm -f "$tmp"
}

install_minikube_mac() {
  log "Installing Minikube via Homebrew..."
  brew install minikube
}

check_minikube() {
  if have minikube; then
    ok "Minikube already installed: $(minikube version --short 2>/dev/null || minikube version 2>/dev/null | head -n1 || echo 'version unknown')"
    return 0
  fi
  log "Minikube not found. Installing..."
  if [ "$OS" = "Darwin" ]; then install_minikube_mac; else install_minikube_linux; fi
  have minikube && ok "Minikube installed: $(minikube version --short 2>/dev/null || echo 'version unknown')"
}

# HELM

install_helm_linux() {
  log "Installing Helm via the official install script..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm-3.sh
  chmod +x /tmp/get-helm-3.sh
  # We're root, so the script can install straight to /usr/local/bin.
  $SUDO /tmp/get-helm-3.sh
  rm -f /tmp/get-helm-3.sh
}

install_helm_mac() {
  log "Installing Helm via Homebrew..."
  brew install helm
}

check_helm() {
  if have helm; then
    ok "Helm already installed: $(helm version --short 2>/dev/null || echo 'version unknown')"
    return 0
  fi
  log "Helm not found. Installing..."
  if [ "$OS" = "Darwin" ]; then install_helm_mac; else install_helm_linux; fi
  have helm && ok "Helm installed: $(helm version --short 2>/dev/null || echo 'version unknown')"
}

# TERRAFORM

install_terraform_linux() {
  case "$PKG" in
    apt)
      log "Installing Terraform via HashiCorp apt repository..."
      curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
      # Update only the newly added HashiCorp repo, then install.
      $SUDO apt-get update
      $SUDO apt-get install -y terraform
      ;;
    dnf)
      log "Installing Terraform via HashiCorp dnf repository..."
      $SUDO dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
      $SUDO dnf -y install terraform
      ;;
    yum)
      log "Installing Terraform via HashiCorp yum repository..."
      $SUDO yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
      $SUDO yum -y install terraform
      ;;
    *)
      err "Cannot install Terraform automatically on this distro. See https://developer.hashicorp.com/terraform/install"
      return 1
      ;;
  esac
}

install_terraform_mac() {
  log "Installing Terraform via Homebrew..."
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform
}

check_terraform() {
  if have terraform; then
    ok "Terraform already installed: $(terraform version 2>/dev/null | head -n1 || echo 'version unknown')"
    return 0
  fi
  log "Terraform not found. Installing..."
  if [ "$OS" = "Darwin" ]; then install_terraform_mac; else install_terraform_linux; fi
  have terraform && ok "Terraform installed: $(terraform version 2>/dev/null | head -n1 || echo 'version unknown')"
}

# REMEDIATION GUIDANCE

# Print help for a tool that failed to install. Called once for each tool that
# is still missing at the end.
remediation_for() {
  case "$1" in
    docker)
      if [ "$IS_WSL" = true ]; then
        warn "docker: not available in this WSL distro."
        warn "  On Windows, install Docker Desktop and enable WSL 2 integration:"
        warn "    1. https://www.docker.com/products/docker-desktop/"
        warn "    2. Settings > General: enable 'Use the WSL 2 based engine'."
        warn "    3. Settings > Resources > WSL Integration: enable ${WSL_DISTRO_NAME:-your distro}."
        warn "    4. Restart this WSL shell, then re-run: sudo ./install-tools.sh"
      elif [ -z "$PKG" ] && [ "$OS" = "Linux" ]; then
        warn "docker: no supported package manager (apt/dnf/yum) was found."
        warn "  Install Docker manually: https://docs.docker.com/engine/install/"
      else
        warn "docker: automatic install did not complete. See the 'docker+terraform'"
        warn "  log above for the error, then follow: https://docs.docker.com/engine/install/"
      fi
      ;;
    kubectl)
      warn "kubectl: automatic install did not complete (see the 'kubectl' log above)."
      warn "  Install manually: https://kubernetes.io/docs/tasks/tools/#kubectl"
      ;;
    minikube)
      warn "minikube: automatic install did not complete (see the 'minikube' log above)."
      warn "  Install manually: https://minikube.sigs.k8s.io/docs/start/"
      ;;
    helm)
      warn "helm: automatic install did not complete (see the 'helm' log above)."
      warn "  Install manually: https://helm.sh/docs/intro/install/"
      ;;
    terraform)
      if [ -z "$PKG" ] && [ "$OS" = "Linux" ]; then
        warn "terraform: no supported package manager (apt/dnf/yum) was found."
        warn "  Install manually: https://developer.hashicorp.com/terraform/install"
      else
        warn "terraform: automatic install did not complete (see the 'docker+terraform' log above)."
        warn "  Install manually: https://developer.hashicorp.com/terraform/install"
      fi
      ;;
  esac
}

# MAC HOMEBREW BOOTSTRAP

ensure_brew() {
  if have brew; then return 0; fi
  log "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in the current shell
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# ORCHESTRATION

# Linux: install tools at the same time to save time. kubectl, minikube and
# helm are simple binary downloads, so they can run fully in parallel. Docker
# and Terraform both use the package manager (apt/dnf/yum), which locks while
# in use, so they run one after the other in their own group.
run_installs_linux() {
  prep_pkg_mgr

  # Group A: binary downloads, safe to run in parallel.
  log "Installing kubectl, Minikube and Helm in parallel..."
  run_bg "kubectl"  check_kubectl
  run_bg "minikube" check_minikube
  run_bg "helm"     check_helm

  # Group B: package-manager installs. Runs alongside Group A, but Docker and
  # Terraform go one at a time so they don't fight over the package lock.
  pkg_group() {
    check_docker || return 1
    check_terraform
  }
  run_bg "docker+terraform" pkg_group

  # main() reports any tools that are still missing, so don't stop on failure
  # here. Just wait for everything to finish and print the logs.
  wait_bg || true
}

# macOS: brew manages its own locking and can break if several copies run at
# once, so install one tool at a time.
run_installs_mac() {
  check_docker || true
  check_kubectl
  check_minikube
  check_helm
  check_terraform
}

# MAIN

main() {
  require_root

  # Remove Windows Zone.Identifier files before anything else, so the later
  # Terraform/Helm steps don't trip over them.
  clean_zone_identifier

  local env_label="$OS"
  [ "$IS_WSL" = true ] && env_label="Windows/WSL ($OS)"
  log "Detected environment: $env_label, architecture: $ARCH${PKG:+, package manager: $PKG}"

  if [ "$OS" = "Darwin" ]; then
    ensure_brew
    run_installs_mac
  elif [ "$OS" = "Linux" ]; then
    run_installs_linux
  else
    err "Unsupported OS: $OS. This script supports Linux, macOS, and Windows (via WSL)."
    exit 1
  fi

  echo
  ok "All done. Summary:"
  printf '  docker:   %s\n' "$(have docker   && docker --version 2>/dev/null || echo 'NOT installed')"
  printf '  kubectl:  %s\n' "$(have kubectl  && kubectl version --client 2>/dev/null | head -n1 || echo 'NOT installed')"
  printf '  minikube: %s\n' "$(have minikube && (minikube version --short 2>/dev/null || minikube version 2>/dev/null | head -n1) || echo 'NOT installed')"
  printf '  helm:     %s\n' "$(have helm && helm version --short 2>/dev/null || echo 'NOT installed')"
  printf '  terraform:%s\n' "$(have terraform && terraform version 2>/dev/null | head -n1 || echo ' NOT installed')"
  echo

  # Collect anything that is still missing after the run.
  local missing=()
  for tool in docker kubectl minikube helm terraform; do
    have "$tool" || missing+=("$tool")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    ok "All required tools are installed."
    log "Next: start your cluster with 'minikube start'"
    return 0
  fi

  # On WSL, a missing Docker is normal (it comes from Docker Desktop on
  # Windows), so treat that one case as OK rather than an error.
  local wsl_docker_only=false
  if [ "$IS_WSL" = true ] && [ "${#missing[@]}" -eq 1 ] && [ "${missing[0]}" = "docker" ]; then
    wsl_docker_only=true
  fi

  err "The following tool(s) could not be installed automatically: ${missing[*]}"
  echo
  warn "How to resolve each one:"
  for tool in "${missing[@]}"; do
    remediation_for "$tool"
  done
  echo
  warn "Fix the item(s) above, then re-run this script:"
  if [ "$OS" = "Darwin" ]; then
    warn "  ./install-tools.sh"
  else
    warn "  sudo ./install-tools.sh"
  fi

  if [ "$wsl_docker_only" = true ]; then
    # Expected on WSL until Docker Desktop integration is turned on, so don't
    # treat it as a failure.
    return 0
  fi

  # Exit with an error so CI or a calling script knows the setup didn't finish.
  return 1
}

main "$@"
