#!/usr/bin/env bash

set -euo pipefail

green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
cyan()  { printf '\033[0;36m%s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[0;33m%s\033[0m\n' "$1"; }

log() { cyan "▶ $1"; }
warn() { yellow "⚠ $1"; }

DOTFILES_REPO="renxiaoyaoo/dotfiles"
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
OS="$(uname)"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    red "This step needs root privileges, but sudo is not installed."
    red "Run as root, or install sudo, then re-run this script."
    exit 1
  fi
}

ensure_macos_prereqs() {
  log "Checking Xcode Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    cyan "Xcode Command Line Tools installation was requested."
    cyan "After it finishes, re-run this script."
    exit 0
  fi

  log "Checking Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
      cyan "$pkg: required for private dotfiles setup"
      brew install "$pkg"
    fi
  done
}

ensure_linux_prereqs() {
  log "Installing Linux bootstrap tools"
  if ! command -v apt-get >/dev/null 2>&1; then
    red "Unsupported Linux package manager. This bootstrap currently supports apt-get systems."
    exit 1
  fi

  as_root apt-get update
  for pkg in curl git ca-certificates; do
    as_root apt-get install -y "$pkg"
  done

  if ! command -v gh >/dev/null 2>&1; then
    if apt-cache show gh >/dev/null 2>&1; then
      as_root apt-get install -y gh
    else
      red "GitHub CLI is not available from this apt repository."
      red "Install gh manually, then re-run this script."
      exit 1
    fi
  fi

  if ! command -v chezmoi >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

ensure_github_auth() {
  log "Checking GitHub authentication"
  if gh auth status >/dev/null 2>&1; then
    green "GitHub CLI already authenticated"
    return
  fi

  warn "GitHub login is required because dotfiles is private."
  cyan "Follow the browser/device-code instructions from gh auth login."
  gh auth login -h github.com -s repo
}

init_or_update_dotfiles() {
  log "Setting up chezmoi source"

  if [ -d "$CHEZMOI_SOURCE/.git" ]; then
    git -C "$CHEZMOI_SOURCE" pull --ff-only
    return
  fi

  if [ -d "$CHEZMOI_SOURCE" ]; then
    red "$CHEZMOI_SOURCE exists but is not a git repository."
    red "Move it aside after checking its contents, then re-run."
    exit 1
  fi

  mkdir -p "$(dirname "$CHEZMOI_SOURCE")"
  gh repo clone "$DOTFILES_REPO" "$CHEZMOI_SOURCE"
}

run_private_bootstrap() {
  chmod +x "$CHEZMOI_SOURCE/files/bootstrap.sh"
  if [ -f "$CHEZMOI_SOURCE/files/doctor.sh" ]; then
    chmod +x "$CHEZMOI_SOURCE/files/doctor.sh"
  fi

  log "Running private dotfiles bootstrap"
  exec "$CHEZMOI_SOURCE/files/bootstrap.sh"
}

log "Public bootstrap entry"
cyan "This script only installs minimal tools and authenticates GitHub."
cyan "Private config stays in $DOTFILES_REPO."

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
run_private_bootstrap
