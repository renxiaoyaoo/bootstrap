# bootstrap

公开的新设备初始化入口。它只负责准备基础工具、登录 GitHub、拉取私有 dotfiles，然后交给 dotfiles 完成个人配置。

## macOS

```sh
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?ts=$(date +%s)" | /bin/bash
```

如果弹出 Xcode Command Line Tools 安装窗口，先完成安装，然后重跑同一条命令。

## Linux / Raspberry Pi OS / Debian / Ubuntu

```sh
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?ts=$(date +%s)" | bash
elif command -v wget >/dev/null 2>&1; then
  wget --no-cache -qO- "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?ts=$(date +%s)" | bash
else
  sudo apt-get update
  sudo apt-get install -y curl
  curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?ts=$(date +%s)" | bash
fi
```

## 初始化后检查

```sh
~/.local/share/chezmoi/files/doctor.sh
```
