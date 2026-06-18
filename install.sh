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
TOTAL_STEPS=6

step() {
  STEP=$((STEP + 1))
  yellow ""
  yellow "[$STEP/$TOTAL_STEPS] $1"
}

tool_reason() {
  case "$1" in
    git) echo "克隆和更新配置仓库。" ;;
    gh) echo "登录 GitHub；后续步骤需要访问你的仓库。" ;;
    chezmoi) echo "把配置仓库应用到当前设备。" ;;
    curl) echo "下载初始化脚本和安装器。" ;;
    ca-certificates) echo "让 HTTPS 下载和 Git 访问正常校验证书。" ;;
    *) echo "初始化流程需要的基础工具。" ;;
  esac
}

notice() {
  local kind="$1"
  local name="$2"
  local reason="$3"

  yellow "============================================================"
  yellow "[$kind] $name"
  cyan "用途: $reason"
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
    red "这一步需要 root 权限，但系统里没有 sudo。"
    red "请用 root 运行，或先安装 sudo，然后重跑初始化命令。"
    exit 1
  fi
}

github_ssh_key_title() {
  local device_name
  device_name="$(ssh_key_device_name)"

  local default_title="$(whoami)@$device_name"
  local title="$default_title"

  if [ -t 0 ]; then
    cyan "SSH key 名称: 只用于 GitHub 页面识别。"
    printf "SSH key 名称 [%s]: " "$default_title"
    read -r title
    [ -z "$title" ] && title="$default_title"
  fi

  echo "$title"
}

ssh_key_device_name() {
  device_short_name | sed 's/[.]local$//'
}

device_short_name() {
  if [ "$OS" = "Darwin" ]; then
    scutil --get HostName 2>/dev/null || scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname
  else
    hostname -s 2>/dev/null || hostname
  fi
}

sanitize_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

sanitize_local_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[.]local$//; s/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

configure_device_name() {
  step "设置设备名称"

  local current_name
  current_name="$(device_short_name)"

  if [ ! -t 0 ]; then
    cyan "非交互环境，保留当前设备名: $current_name"
    return
  fi

  if [ "$OS" = "Darwin" ]; then
    local current_computer current_local
    local computer_name network_name network_suggestion raw_name safe_name changed

    current_computer="$(scutil --get ComputerName 2>/dev/null || device_short_name)"
    current_local="$(scutil --get LocalHostName 2>/dev/null || sanitize_local_hostname "$current_computer")"

    cyan "ComputerName: 关于本机/共享显示名，可有空格。"
    printf "ComputerName [%s]: " "$current_computer"
    read -r computer_name
    [ -z "$computer_name" ] && computer_name="$current_computer"

    network_suggestion="$(sanitize_local_hostname "$computer_name")"
    [ -z "$network_suggestion" ] && network_suggestion="$current_local"
    cyan "网络/SSH 名称: 输入基础名即可；访问时是 ${network_suggestion}.local。"
    printf "网络/SSH 名称 [%s]: " "$network_suggestion"
    read -r raw_name
    [ -z "$raw_name" ] && raw_name="$network_suggestion"
    safe_name="$(sanitize_local_hostname "$raw_name")"
    if [ "$raw_name" != "$safe_name" ] && [ "$raw_name" != "${safe_name}.local" ]; then
      cyan "网络/SSH 名称将使用: ${safe_name}"
    fi
    network_name="$safe_name"

    if [ -z "$network_name" ]; then
      red "设备名无效，保留当前值。"
      return
    fi

    notice "需要设置" "macOS 设备名称" "设置显示名、局域网名和 SSH/终端识别名。"
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
      green "Device name already configured: $network_name"
    else
      green "Device name configured: $network_name"
    fi
  elif command -v hostnamectl >/dev/null 2>&1; then
    local raw_name safe_name

    cyan "设置 Linux hostname。回车使用方括号里的建议值。"
    cyan "HostName: 局域网、SSH、终端和服务识别使用；Linux 通常用短名称。"
    printf "HostName（局域网、SSH 和服务识别）[%s]: " "$current_name"
    read -r raw_name
    [ -z "$raw_name" ] && raw_name="$current_name"
    safe_name="$(sanitize_hostname "$raw_name")"
    if [ "$safe_name" != "$raw_name" ]; then
      cyan "HostName 将使用安全值: $safe_name"
    fi

    if [ -z "$safe_name" ]; then
      red "设备名无效，保留当前值: $current_name"
      return
    fi

    if [ "$(hostnamectl --static 2>/dev/null || hostname)" = "$safe_name" ]; then
      green "Device name already configured: $safe_name"
      return
    fi

    notice "需要设置" "Linux hostname" "用于局域网、SSH 和服务识别。"
    as_root hostnamectl set-hostname "$safe_name"
    green "Device name configured: $safe_name"
  else
    yellow "当前 Linux 没有 hostnamectl，跳过持久化设备名。"
    cyan "如需设置，请按发行版方式手动配置 hostname: $safe_name"
  fi
}

ensure_macos_prereqs() {
  step "检查 macOS 基础依赖"
  log "Checking Xcode Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    notice "必需安装" "Xcode Command Line Tools" "提供 git、编译工具和 Homebrew 依赖的系统开发工具。"
    xcode-select --install || true
    cyan "已请求安装 Xcode Command Line Tools。"
    cyan "安装完成后，重新运行这条初始化命令。"
    exit 0
  fi

  log "Checking Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    else
      notice "必需安装" "Homebrew" "macOS 包管理器，用来安装 git、gh、chezmoi。"
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
      notice_tool "必需安装" "$pkg"
      brew install "$pkg"
    fi
  done
}

ensure_linux_prereqs() {
  step "检查 Linux 基础依赖"
  log "Installing Linux bootstrap tools"
  if ! command -v apt-get >/dev/null 2>&1; then
    red "当前 Linux 包管理器暂不支持。这个初始化脚本目前只支持 apt-get 系统。"
    exit 1
  fi

  as_root apt-get update
  for pkg in curl git ca-certificates; do
    notice_tool "必需安装/检查" "$pkg"
    as_root apt-get install -y "$pkg"
  done

  if ! command -v gh >/dev/null 2>&1; then
    if apt-cache show gh >/dev/null 2>&1; then
      notice_tool "必需安装" "gh"
      as_root apt-get install -y gh
    else
      red "当前 apt 源里没有 GitHub CLI。"
      red "请先手动安装 gh，然后重跑初始化命令。"
      exit 1
    fi
  fi

  if ! command -v chezmoi >/dev/null 2>&1; then
    notice_tool "必需安装" "chezmoi"
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

ensure_github_auth() {
  step "检查 GitHub 登录"
  log "Checking GitHub authentication"
  if gh auth status >/dev/null 2>&1; then
    green "GitHub CLI already authenticated"
    return
  fi

  warn "GitHub login is required for the next setup step."
  cyan "请按 gh auth login 显示的浏览器或设备码提示完成登录。"
  gh auth login -h github.com -s repo
}

ensure_github_ssh() {
  step "配置 GitHub SSH"
  log "Configuring GitHub SSH"

  local key_title
  key_title="$(github_ssh_key_title)"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    notice "必需生成" "SSH key" "用于通过 SSH 拉取和推送 GitHub 仓库。"
    ssh-keygen -t ed25519 -C "$key_title" -f "$HOME/.ssh/id_ed25519" -N ""
  fi

  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    cyan "Adding SSH key to GitHub: $key_title"
    if gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$key_title" >/dev/null 2>&1; then
      green "SSH key registered"
    else
      cyan "SSH key may already exist, continue"
    fi
  fi

  gh config set git_protocol ssh -h github.com >/dev/null
}

init_or_update_dotfiles() {
  step "拉取配置仓库"
  log "Setting up chezmoi source"

  if [ -z "$DOTFILES_REPO" ]; then
    github_user="$(gh api user --jq .login)"
    DOTFILES_REPO="$github_user/dotfiles"
  fi
  DOTFILES_SSH_URL="git@github.com:$DOTFILES_REPO.git"

  if [ -d "$CHEZMOI_SOURCE/.git" ]; then
    current_url="$(git -C "$CHEZMOI_SOURCE" remote get-url origin 2>/dev/null || true)"
    case "$current_url" in
      https://github.com/*)
        cyan "已存在的配置仓库使用 HTTPS，切换为 SSH。"
        git -C "$CHEZMOI_SOURCE" remote set-url origin "$DOTFILES_SSH_URL"
        ;;
    esac
    git -C "$CHEZMOI_SOURCE" pull --ff-only
    return
  fi

  if [ -d "$CHEZMOI_SOURCE" ]; then
    red "$CHEZMOI_SOURCE 已存在，但不是 Git 仓库。"
    red "请先确认里面内容，移走或备份后再重跑初始化命令。"
    exit 1
  fi

  mkdir -p "$(dirname "$CHEZMOI_SOURCE")"
  git clone "$DOTFILES_SSH_URL" "$CHEZMOI_SOURCE"
}

run_dotfiles_bootstrap() {
  chmod +x "$CHEZMOI_SOURCE/files/bootstrap.sh"
  if [ -f "$CHEZMOI_SOURCE/files/doctor.sh" ]; then
    chmod +x "$CHEZMOI_SOURCE/files/doctor.sh"
  fi

  step "运行初始化脚本"
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
configure_device_name
ensure_github_ssh
init_or_update_dotfiles
run_dotfiles_bootstrap
