# bootstrap

公开的新设备初始化入口。它只负责准备基础工具、登录 GitHub、拉取私有 dotfiles，然后交给 dotfiles 完成个人配置。

## 初始化

```sh
curl -fsSL "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?$(date +%s)" -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

如果弹出 Xcode Command Line Tools 安装窗口，先完成安装，然后重跑同一条命令。
如果 Linux 没有 `curl`，先运行：`sudo apt-get update && sudo apt-get install -y curl`

## 初始化后检查

```sh
~/.local/share/chezmoi/files/doctor.sh
```
