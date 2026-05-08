#!/bin/sh
# laptop-snapshot.sh — TEMPLATE
#
# Snapshot laptop configs into ~/dotfiles, commit, push.
# Triggered by ~/Library/LaunchAgents/com.<you>.dotfiles-backup.plist via fswatch.
# Logs to /tmp/dotfiles-backup.{out,err}.
#
# CUSTOMIZATION: edit the WHITELISTED FILES section below to match what you want
# to track. Out of the box this assumes a Claude Code user with ~/.claude config
# plus a few common shell rc files.

set -u
ROOT="$HOME/dotfiles"
cd "$ROOT" || exit 1

# launchd jobs start with a minimal PATH — homebrew + system bins
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

# Sync with remote first so other hosts' commits don't trigger non-fast-forward rejection
git pull --rebase --autostash 2>>/tmp/dotfiles-backup.err || {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pull --rebase failed; aborting" >>/tmp/dotfiles-backup.err
  exit 0
}

# ===== WHITELISTED FILES — edit this block =====

# Example: ~/.claude tracked subset (Claude Code config)
mkdir -p "$ROOT/claude"
for f in CLAUDE.md settings.json statusline-command.sh; do
  [ -f "$HOME/.claude/$f" ] && cp -p "$HOME/.claude/$f" "$ROOT/claude/$f"
done
for d in plans agents commands skills; do
  [ -d "$HOME/.claude/$d" ] && rsync -a --delete "$HOME/.claude/$d/" "$ROOT/claude/$d/"
done

# Laptop home dotfiles
mkdir -p "$ROOT/laptop"
for f in .zshrc .bashrc .vimrc .gitconfig; do
  [ -f "$HOME/$f" ] && cp -p "$HOME/$f" "$ROOT/laptop/$f"
done

# ===== END WHITELIST =====

git add -A
git diff --cached --quiet && exit 0
git commit -m "auto: laptop $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
git push 2>>/tmp/dotfiles-backup.err || {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) push failed (commit retained locally)" >>/tmp/dotfiles-backup.err
  exit 0
}
