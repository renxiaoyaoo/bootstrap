#!/usr/bin/env bash

set -euo pipefail

green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
cyan()  { printf '\033[0;36m%s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[0;33m%s\033[0m\n' "$1"; }

log() { cyan "▶ $1"; }
warn() { yellow "⚠ $1"; }

DOTFILES_REPO="${DOTFILES_REPO:-}"
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
OS="$(uname)"
STEP=0
TOTAL_STEPS=4

step() {
  STEP=$((STEP + 1))
  yellow ""
  yellow "[$STEP/$TOTAL_STEPS] $1"
}

tool_reason() {
  case "$1" in
    git) echo "Clone and update repositories." ;;
    gh) echo "GitHub login for private repositories." ;;
    chezmoi) echo "Apply dotfiles to this device." ;;
    curl) echo "Download bootstrap scripts and installers." ;;
    ca-certificates) echo "Verify HTTPS downloads and Git connections." ;;
    *) echo "Required by the bootstrap flow." ;;
  esac
}

notice() {
  local kind="$1"
  local name="$2"
  local reason="$3"

  yellow "============================================================"
  yellow "[$kind] $name"
  cyan "Why: $reason"
  yellow "============================================================"
}

notice_tool() {
  notice "$1" "$2" "$(tool_reason "$2")"
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    red "Root permission is required, but sudo is not available."
    red "Run as root or install sudo, then rerun this command."
    exit 1
  fi
}

ensure_macos_prereqs() {
  step "Check macOS prerequisites"
  log "Checking Xcode Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    notice "Required" "Xcode Command Line Tools" "Provides git, compilers, and Homebrew system dependencies."
    xcode-select --install || true
    cyan "Xcode Command Line Tools install requested."
    cyan "After it finishes, rerun the bootstrap command."
    exit 0
  fi

  log "Checking Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    else
      notice "Required" "Homebrew" "macOS package manager for git, gh, and chezmoi."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  log "Installing bootstrap tools"
  for pkg in git gh chezmoi; do
    if brew list "$pkg" >/dev/null 2>&1; then
      green "$pkg already installed"
    else
      notice_tool "Required" "$pkg"
      brew install "$pkg"
    fi
  done
}

ensure_linux_prereqs() {
  step "Check Linux prerequisites"
  log "Installing Linux bootstrap tools"
  if ! command -v apt-get >/dev/null 2>&1; then
    red "Unsupported Linux package manager. This bootstrap currently supports apt-get systems."
    exit 1
  fi

  as_root apt-get update
  for pkg in curl git ca-certificates; do
    notice_tool "Required/check" "$pkg"
    as_root apt-get install -y "$pkg"
  done

  if ! command -v gh >/dev/null 2>&1; then
    if apt-cache show gh >/dev/null 2>&1; then
      notice_tool "Required" "gh"
      as_root apt-get install -y gh
    else
      red "GitHub CLI is not available from the current apt sources."
      red "Install gh manually, then rerun this command."
      exit 1
    fi
  fi

  if ! command -v chezmoi >/dev/null 2>&1; then
    notice_tool "Required" "chezmoi"
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

ensure_github_auth() {
  step "Check GitHub login"
  log "Checking GitHub authentication"
  if gh auth status >/dev/null 2>&1; then
    green "GitHub CLI already authenticated"
    return
  fi

  warn "GitHub login is required for the next setup step."
  cyan "Follow the browser or device-code prompt from gh auth login."
  gh auth login -h github.com -s repo
}

init_or_update_dotfiles() {
  step "Fetch dotfiles"
  log "Setting up chezmoi source"

  if [ -z "$DOTFILES_REPO" ]; then
    github_user="$(gh api user --jq .login)"
    DOTFILES_REPO="$github_user/dotfiles"
  fi
  gh config set git_protocol https -h github.com >/dev/null

  if [ -d "$CHEZMOI_SOURCE/.git" ]; then
    git -C "$CHEZMOI_SOURCE" pull --ff-only
    return
  fi

  if [ -d "$CHEZMOI_SOURCE" ]; then
    red "$CHEZMOI_SOURCE exists but is not a Git repository."
    red "Move or back it up, then rerun this command."
    exit 1
  fi

  mkdir -p "$(dirname "$CHEZMOI_SOURCE")"
  gh repo clone "$DOTFILES_REPO" "$CHEZMOI_SOURCE"
}

run_dotfiles_bootstrap() {
  chmod +x "$CHEZMOI_SOURCE/files/bootstrap.sh"
  if [ -f "$CHEZMOI_SOURCE/files/doctor.sh" ]; then
    chmod +x "$CHEZMOI_SOURCE/files/doctor.sh"
  fi

  step "Run dotfiles bootstrap"
  log "Running dotfiles bootstrap"
  exec "$CHEZMOI_SOURCE/files/bootstrap.sh"
}

log "Public bootstrap entry"
cyan "This script only installs minimal tools and authenticates GitHub."
cyan "Personal config is handled after authentication."

case "$OS" in
  Darwin) ensure_macos_prereqs ;;
  Linux) ensure_linux_prereqs ;;
  *)
    red "Unsupported OS: $OS"
    exit 1
    ;;
esac

ensure_github_auth
init_or_update_dotfiles
run_dotfiles_bootstrap
