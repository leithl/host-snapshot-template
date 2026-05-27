# host-snapshot-template

A pattern for **automatically backing up host configuration to private git repos** across multiple machines. Two layers, both push themselves to git on a timer:

1. **`dotfiles/`** — user-level configs (`~/.zshrc`, `~/.config/`, etc.). Each host runs a snapshot script that copies whitelisted files into a host-specific subdir, then commits and pushes.
2. **`etc/`** — system-level config (`/etc/`). Managed by [`etckeeper`](https://etckeeper.branchable.com/) (a wrapper around git that hooks into `apt`/`dpkg` for instant commits on package install). Plus a pre-commit hook that captures non-`/etc` rebuild artifacts (package manifest, kernel info, custom scripts in `/usr/local/bin/`, crontabs, iptables state) into `/etc/system-snapshot/`.

Each layer pushes to its own private repo. **Together they form a catastrophic-rebuild kit per host** — clone the two repos on a fresh OS install, run the included `restore.sh`, and you're 90% back. The remaining 10% is deliberately not tracked: passwords, SSH host keys, TLS private keys, mail-relay creds. Those are listed in the README of each repo so you know what to recreate.

## What's in this template

- Working scripts you adapt by changing `<HOST>` / `<USER>` / `<GH_USERNAME>` placeholders
- A thoroughly-tested **secret-exclusion gitignore** for `/etc/` (see warning below)
- A `restore.sh` template that bootstraps a fresh box from the two repos
- READMEs in each subdir explaining the pattern, how to adopt it, and what each piece does

## Read this before adopting the `etc/` half

> **etckeeper's default config tracks `/etc/shadow`, `/etc/gshadow`, and `/etc/ssh/ssh_host_*_key`.** Its assumed use case is local-disk git, not remote pushing. The very first commit after `etckeeper init` will leak password hashes and host private keys to your remote unless `/etc/.gitignore` is in place beforehand.

`etc/gitignore.secrets` in this repo is the comprehensive exclude list — drop it into `/etc/.gitignore` *before* running `etckeeper init`. The `etc/README.md` walks through the full setup, in the right order.

(Yes, this happened to the author of this template. Recovery: delete the repo on GitHub, rotate the host keys, redo with the gitignore in place. ~5 minutes if you catch it fast. Hours of paranoia if you don't.)

## Two-host shape this template assumes

The template is sized for a small fleet — one personal laptop (macOS) plus one or two Linux servers. It scales to more, but you'll start wanting tooling like Ansible or NixOS at ~5+ hosts.

| Layer | Trigger on macOS | Trigger on Linux |
|---|---|---|
| dotfiles | `LaunchAgent` watching `~/.claude/` (or wherever) via `fswatch` | `cron */15 * * * *` |
| etc      | n/a — `/etc` is Linux-specific | etckeeper auto-hooks on `apt`/`dpkg` + `cron.daily` |

Push auth pattern: `gh` CLI HTTPS token on the laptop, per-host SSH deploy keys on the Linux side.

## Getting started

1. Read [`dotfiles/README.md`](./dotfiles/README.md) and [`etc/README.md`](./etc/README.md).
2. Create two private repos on your GitHub: `<you>/dotfiles` and `<you>/<hostname>-etc` (one per Linux host you'll back up).
3. On each host, follow the adoption checklist in the matching subdir README.
4. Within an hour you should have your first auto-commits landing in both repos.

## License

MIT — see [LICENSE](./LICENSE).

## Lineage

Extracted from a working personal setup; this template is the de-personalized version that captures the pattern.
