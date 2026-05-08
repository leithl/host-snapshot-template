#!/bin/sh
# linux-snapshot.sh — TEMPLATE
#
# Generic Linux host snapshot. Rename to `<host>-snapshot.sh` (e.g. `webserver-snapshot.sh`)
# and update the `<host>` references below. Run via cron */15.
#
# Logs to /tmp/dotfiles-backup.{out,err}.
#
# CUSTOMIZATION: edit the WHITELISTED FILES section to match what you want to track
# AND change the subdir from <host> to your host's actual name in 3 places below.

set -u
ROOT="$HOME/dotfiles"
HOST="<host>"   # e.g. "webserver" — used as the subdir name + commit message tag
cd "$ROOT" || exit 1

PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

# Sync with remote first so other hosts' commits don't trigger non-fast-forward rejection
git pull --rebase --autostash 2>>/tmp/dotfiles-backup.err || {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pull --rebase failed; aborting" >>/tmp/dotfiles-backup.err
  exit 0
}

# ===== WHITELISTED FILES — edit this block =====

mkdir -p "$ROOT/$HOST"

# Common shell + git rc files
for f in .bashrc .gitconfig .profile .vimrc; do
  [ -f "$HOME/$f" ] && cp -p "$HOME/$f" "$ROOT/$HOST/$f"
done

# User-level crontab (whatever you have set up)
crontab -l > "$ROOT/$HOST/crontab.txt" 2>/dev/null || true

# Example: rsync a user scripts directory
[ -d "$HOME/scripts" ] && rsync -a --delete "$HOME/scripts/" "$ROOT/$HOST/scripts/"

# Example: capture a specific app's config (~/.config/<app>) but only certain files
# [ -d "$HOME/.config/myapp" ] && rsync -a --delete \
#   --include='/config.yaml' --include='/profile.json' --exclude='/*' \
#   "$HOME/.config/myapp/" "$ROOT/$HOST/myapp/"

# ===== END WHITELIST =====

git add -A
git diff --cached --quiet && exit 0
git commit -m "auto: $HOST $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
git push 2>>/tmp/dotfiles-backup.err || {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) push failed (commit retained locally)" >>/tmp/dotfiles-backup.err
  exit 0
}
