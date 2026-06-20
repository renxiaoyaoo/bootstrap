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
TOTAL_STEPS=5

step() {
  STEP=$((STEP + 1))
  yellow ""
  yellow "[$STEP/$TOTAL_STEPS] $1"
}

tool_reason() {
  case "$1" in
    git) echo "Clone and update repositories." ;;
    openssh-client) echo "Create SSH keys and connect to GitHub over SSH." ;;
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

has_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_read() {
  local __var="$1"
  local __value
  if has_tty; then
    IFS= read -r __value < /dev/tty
  else
    __value=""
  fi
  eval "$__var=\$__value"
}

device_short_name() {
  if [ "$OS" = "Darwin" ]; then
    scutil --get HostName 2>/dev/null || scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname
  else
    hostname -s 2>/dev/null || hostname
  fi
}

sanitize_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[.]local$//; s/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

ssh_key_device_name() {
  device_short_name | sed 's/[.]local$//'
}

github_ssh_key_title() {
  local default_title title
  default_title="$(whoami)@$(ssh_key_device_name)"
  title="$default_title"

  if has_tty; then
    cyan "SSH key title: 只用于 GitHub 页面识别这台设备；回车用默认值，也可以输入自定义名称。" > /dev/tty
    printf "SSH key title [%s]: " "$default_title" > /dev/tty
    prompt_read title
    [ -z "$title" ] && title="$default_title"
  fi

  echo "$title"
}

configure_device_name() {
  step "Set device name"

  local current_name
  current_name="$(device_short_name)"

  if ! has_tty; then
    cyan "Non-interactive shell; keeping current device name: $current_name"
    return
  fi

  if [ "$OS" = "Darwin" ]; then
    local current_computer current_host current_local current_hostname current_network
    local computer_name network_suggestion raw_name network_name changed

    current_computer="$(scutil --get ComputerName 2>/dev/null || device_short_name)"
    current_host="$(scutil --get HostName 2>/dev/null || true)"
    current_local="$(scutil --get LocalHostName 2>/dev/null || true)"
    current_hostname="$(hostname -s 2>/dev/null || hostname)"
    current_network="$(device_short_name)"

    cyan "Current: ComputerName=${current_computer:-unset}, HostName=${current_host:-unset}, LocalHostName=${current_local:-unset}, hostname=${current_hostname:-unset}"
    cyan "ComputerName: 关于本机/共享里显示的名字，可以包含空格。"
    printf "ComputerName [%s]: " "$current_computer"
    prompt_read computer_name
    [ -z "$computer_name" ] && computer_name="$current_computer"

    if [ "$computer_name" = "$current_computer" ] && [ -n "$current_network" ]; then
      network_suggestion="$(sanitize_hostname "$current_network")"
    else
      network_suggestion="$(sanitize_hostname "$computer_name")"
      [ -z "$network_suggestion" ] && network_suggestion="$(sanitize_hostname "$current_network")"
    fi

    cyan "Network/SSH name: 只输入基础名即可；局域网访问时会是 ${network_suggestion}.local。"
    printf "Network/SSH name [%s]: " "$network_suggestion"
    prompt_read raw_name
    [ -z "$raw_name" ] && raw_name="$network_suggestion"
    network_name="$(sanitize_hostname "$raw_name")"

    if [ -z "$network_name" ]; then
      red "Invalid device name; keeping current values."
      return
    fi

    notice "Required" "macOS device name" "设置显示名、局域网名，以及 SSH/终端里识别这台设备的名字。"
    changed=0
    if [ "$(scutil --get ComputerName 2>/dev/null || true)" != "$computer_name" ]; then
      as_root scutil --set ComputerName "$computer_name"
      changed=1
    fi
    if [ "$(scutil --get LocalHostName 2>/dev/null || true)" != "$network_name" ]; then
      as_root scutil --set LocalHostName "$network_name"
      changed=1
    fi
    if [ "$(scutil --get HostName 2>/dev/null || true)" != "$network_name" ]; then
      as_root scutil --set HostName "$network_name"
      changed=1
    fi

    if [ "$changed" -eq 0 ]; then
      green "Device name already current: $network_name"
    else
      green "Device name configured: $network_name"
    fi
  elif command -v hostnamectl >/dev/null 2>&1; then
    local raw_name safe_name

    cyan "Set Linux hostname. Press Enter to use the suggested value."
    cyan "HostName: 用于局域网、SSH、终端和服务识别；Linux 通常用短名称。"
    printf "HostName [%s]: " "$current_name"
    prompt_read raw_name
    [ -z "$raw_name" ] && raw_name="$current_name"
    safe_name="$(sanitize_hostname "$raw_name")"

    if [ -z "$safe_name" ]; then
      red "Invalid device name; keeping current value: $current_name"
      return
    fi

    if [ "$(hostnamectl --static 2>/dev/null || hostname)" = "$safe_name" ]; then
      green "Device name already current: $safe_name"
      return
    fi

    notice "Required" "Linux hostname" "用于局域网、SSH、终端和服务识别。"
    as_root hostnamectl set-hostname "$safe_name"
    green "Device name configured: $safe_name"
  else
    yellow "hostnamectl is not available; persistent hostname setup skipped."
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
  for pkg in curl git ca-certificates openssh-client; do
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
  log "Checking GitHub authentication"
  if ! gh auth status >/dev/null 2>&1; then
    warn "GitHub login is required for private repositories and this device SSH key."
    cyan "Follow the browser or device-code prompt from gh auth login."
    gh auth login -h github.com --scopes "repo,admin:public_key" --git-protocol https
    return
  fi

  if gh auth status -h github.com 2>&1 | grep -Eq "Token scopes:.*admin:public_key"; then
    green "GitHub CLI already authenticated"
    return
  fi

  warn "GitHub CLI needs one permission upgrade for this device SSH key."
  cyan "Complete the browser or device-code prompt once; existing login is retained."
  gh auth refresh -h github.com --scopes "repo,admin:public_key"
}

configure_github_ssh() {
  log "Checking SSH key"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if ! ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
    log "Adding GitHub SSH host keys"
    gh api meta --jq '.ssh_keys[]' | sed 's#^#github.com #' >> "$HOME/.ssh/known_hosts"
    chmod 600 "$HOME/.ssh/known_hosts"
  fi

  local key_title=""
  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    key_title="$(github_ssh_key_title)"
    notice "Required" "SSH key" "Access private GitHub repositories over SSH."
    ssh-keygen -t ed25519 -C "$key_title" -f "$HOME/.ssh/id_ed25519" -N ""
  fi

  local public_key
  public_key="$(cat "$HOME/.ssh/id_ed25519.pub")"

  local github_keys
  if ! github_keys="$(gh ssh-key list --json key --jq '.[].key')"; then
    red "Cannot read GitHub SSH keys. Rerun and complete GitHub authorization."
    return 1
  fi

  if printf '%s\n' "$github_keys" | grep -Fx "$public_key" >/dev/null 2>&1; then
    green "SSH key already exists on GitHub"
  else
    [ -n "$key_title" ] || key_title="$(github_ssh_key_title)"
    notice "Required" "GitHub SSH key" "Upload this device key to GitHub with a stable device title."
    if gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$key_title"; then
      green "SSH key added to GitHub: $key_title"
    else
      red "GitHub SSH key upload failed."
      red "Fix GitHub authorization and rerun; dotfiles will not be fetched yet."
      return 1
    fi
  fi

  gh config set git_protocol ssh -h github.com >/dev/null
}

configure_github_access() {
  step "Configure GitHub access"
  ensure_github_auth
  configure_github_ssh
}

init_or_update_dotfiles() {
  step "Fetch dotfiles"
  log "Setting up chezmoi source"

  if [ -z "$DOTFILES_REPO" ]; then
    github_user="$(gh api user --jq .login)"
    DOTFILES_REPO="$github_user/dotfiles"
  fi
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
cyan "This script prepares device identity, GitHub access, and private dotfiles."
cyan "Personal config is handled by dotfiles after clone."

case "$OS" in
  Darwin) ensure_macos_prereqs ;;
  Linux) ensure_linux_prereqs ;;
  *)
    red "Unsupported OS: $OS"
    exit 1
    ;;
esac

configure_device_name
configure_github_access
init_or_update_dotfiles
run_dotfiles_bootstrap
