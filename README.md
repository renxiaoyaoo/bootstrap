# bootstrap

Public bootstrap for private `renxiaoyaoo/dotfiles`.

This repository must stay public and must not contain secrets. It only installs minimal tools, logs in to GitHub, clones the private dotfiles repository into `~/.local/share/chezmoi`, and runs the private bootstrap script.

## macOS

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh)"
```

If Xcode Command Line Tools opens an installer, finish it and run the same command again.

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

## What happens

- Installs minimal prerequisites: `git`, `gh`, `chezmoi`.
- Runs `gh auth login` because `dotfiles` is private.
- Clones `renxiaoyaoo/dotfiles` to `~/.local/share/chezmoi`.
- Runs `~/.local/share/chezmoi/files/bootstrap.sh`.

## After setup

Check the device:

```sh
~/.local/share/chezmoi/files/doctor.sh
```

Daily dotfiles maintenance happens in:

```sh
~/.local/share/chezmoi
```
