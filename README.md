# bootstrap

公开的新设备初始化入口，用来启动私有仓库 `renxiaoyaoo/dotfiles`。

这个仓库必须保持公开，并且不能放任何密钥、token、私钥或真实配置。它只做最小引导：

- 安装 `git`、`gh`、`chezmoi`
- 引导 `gh auth login`
- 把私有 `renxiaoyaoo/dotfiles` 克隆到 `~/.local/share/chezmoi`
- 执行私有仓库里的 `~/.local/share/chezmoi/files/bootstrap.sh`

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

## 执行完成后

检查当前设备：

```sh
~/.local/share/chezmoi/files/doctor.sh
```

日常维护 dotfiles 的主目录是：

```sh
~/.local/share/chezmoi
```

日常流程：

```sh
# 直接改真实配置文件
vim ~/.ssh/config

# 收进 chezmoi source
chezmoi add ~/.ssh/config

# 提交并推送
cd ~/.local/share/chezmoi
git diff
git add .
git commit -m "Update dotfiles"
git push
```

另一台设备同步：

```sh
cd ~/.local/share/chezmoi
git pull --ff-only
chezmoi apply
```
