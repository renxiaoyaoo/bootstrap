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

init_or_update_dotfiles() {
  step "拉取配置仓库"
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
    red "$CHEZMOI_SOURCE 已存在，但不是 Git 仓库。"
    red "请先确认里面内容，移走或备份后再重跑初始化命令。"
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
init_or_update_dotfiles
run_dotfiles_bootstrap
