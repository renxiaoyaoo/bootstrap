# bootstrap

公开的新设备初始化入口。

## macOS

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh)"
```

如果弹出 Xcode Command Line Tools 安装窗口，先完成安装，然后重跑同一条命令。

## Linux / Raspberry Pi OS / Debian / Ubuntu

```sh
if command -v curl >/dev/null 2>&1; then
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh)"
elif command -v wget >/dev/null 2>&1; then
  bash -c "$(wget -qO- https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh)"
else
  sudo apt-get update
  sudo apt-get install -y curl
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh)"
fi
```

## 检查

```sh
~/.local/share/chezmoi/files/doctor.sh
```
