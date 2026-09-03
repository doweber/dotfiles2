# dotfiles2

My Linux config and tool list, managed with [chezmoi](https://www.chezmoi.io/).

## New machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply doweber/dotfiles2
```

That installs chezmoi, clones this repo to `~/.local/share/chezmoi`, asks for a git
name/email (once), installs the packages from `.chezmoidata/packages.yaml`
(Arch-based systems only, needs sudo), pulls in tmux's plugin manager, and writes
every config file into place.

Afterwards, in tmux press `prefix + I` once to install the tmux plugins. Neovim
installs its own plugins on first launch.

## Day to day

| What | Command |
| --- | --- |
| See what differs between this repo and the machine | `chezmoi status` / `chezmoi diff` |
| Edited a file in place and want to keep it | `chezmoi re-add` |
| Start tracking a new file | `chezmoi add ~/.config/foo/bar` |
| Apply changes from the repo to the machine | `chezmoi apply` |
| Pull the latest from GitHub and apply | `chezmoi update` |
| Edit a managed file | `chezmoi edit ~/.bashrc` |
| Commit and push | `chezmoi cd` then `git commit` / `git push` |

Adding a package: edit `.chezmoidata/packages.yaml` and run `chezmoi apply`. The
install script re-runs only when that file changes.

Machine-specific hardware packages live under `packages.hosts.<hostname>` in the
same file.

## What is in here

- `dot_bashrc`, `dot_bash_aliases`, `dot_config/bash/prompt.sh`, `dot_inputrc`
- `dot_zshrc`, `dot_p10k.zsh`
- `dot_gitconfig.tmpl` (name/email come from `~/.config/chezmoi/chezmoi.toml`)
- `dot_tmux.conf` (+ tpm via `.chezmoiexternal.toml`)
- `dot_config/nvim` (NvChad v2.5 starter with custom plugins, lockfile included)
- `dot_config/{alacritty,btop,htop,gh,git,Code}`
- `dot_claude/settings.json`, `dot_config/opencode`
- `dot_local/bin`: `davinci-resolve` wrapper, `resolve-transcode`
- `dot_local/share/nautilus/scripts`: right-click media conversion scripts
- `.chezmoidata/packages.yaml` + `.chezmoiscripts/`: declared package list and installer
