# bootstrap

Public entrypoint for a new device. It installs the minimum tools, logs in to GitHub, fetches private dotfiles, then hands off personal setup to dotfiles.

## Start

```sh
curl -fsSL "https://raw.githubusercontent.com/renxiaoyaoo/bootstrap/master/install.sh?$(date +%s)" -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

If Xcode Command Line Tools opens an installer, finish it and rerun the same command.
If Linux does not have `curl`, run: `sudo apt-get update && sudo apt-get install -y curl`

## Check

```sh
~/.local/share/chezmoi/files/doctor.sh
```
