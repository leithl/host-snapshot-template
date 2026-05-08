# dotfiles pattern

User-level config snapshot. Each host runs a script that copies whitelisted files from `$HOME` into a host-specific subdir of a single shared repo, then commits and pushes. Repo becomes a derived view of live config — edits happen in canonical locations (`~/.zshrc`, `~/.config/foo/bar.conf`), not in the repo.

## Suggested layout

```
your-dotfiles/
├── README.md
├── .gitignore
├── claude/         # if you use Claude Code: ~/.claude tracked subset
├── laptop/         # your laptop's dotfiles
├── <host1>/        # each Linux box gets its own subdir
├── <host2>/
└── bin/
    ├── laptop-snapshot.sh
    ├── <host1>-snapshot.sh    # rename linux-snapshot.sh per host
    ├── <host2>-snapshot.sh
    └── com.<you>.dotfiles-backup.plist  # macOS LaunchAgent
```

The whitelist of *what* each host snapshots lives inside that host's script. To add a new tracked file, edit the script.

## How each host triggers

| Host | Trigger | Why |
|---|---|---|
| Laptop (macOS) | `LaunchAgent` running `fswatch` on a directory of interest, debounced 30s | Edits are interactive — you want commits within ~30s of saving, not 15 min later |
| Linux host | `cron */15 * * * *` | Edits are rare (.bashrc, configs); 15-min lag is fine; cron is dead simple |

Both run the same shape of script. Both auto-resolve via `git pull --rebase --autostash` before committing, so cross-host pushes don't trip non-fast-forward rejection.

## Push auth

| Host | Method |
|---|---|
| Laptop (macOS) | `gh` CLI's stored HTTPS token (after one-time `gh auth login`) |
| Linux | Per-host SSH deploy key with write access on the dotfiles repo |

The deploy keys are scoped *to one repo* — if a Linux host is compromised, only that host's deploy key is exposed and only the dotfiles repo is reachable from it.

## Adoption checklist

### One-time GitHub setup
1. Create a **private** repo (e.g. `<you>/dotfiles`).

### On the macOS laptop
2. `gh auth login` (HTTPS, with `repo` scope).
3. `gh repo clone <you>/dotfiles ~/dotfiles`
4. Copy `bin/laptop-snapshot.sh` into the clone, edit the whitelist for what you want tracked. Same for `bin/com.<you>.dotfiles-backup.plist.template` → save as `bin/com.<you>.dotfiles-backup.plist`.
5. `chmod +x bin/laptop-snapshot.sh`
6. Place the LaunchAgent: `cp bin/com.<you>.dotfiles-backup.plist ~/Library/LaunchAgents/`
7. `launchctl load ~/Library/LaunchAgents/com.<you>.dotfiles-backup.plist`
8. Test: `~/dotfiles/bin/laptop-snapshot.sh` — should produce a commit + push.

### On each Linux host
2. Generate a deploy key:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/dotfiles_deploy -N "" -C "<host>-dotfiles"
   cat ~/.ssh/dotfiles_deploy.pub  # paste this into GitHub Settings → Deploy keys (with write access)
   ```
3. Add an SSH config alias:
   ```bash
   cat >> ~/.ssh/config <<'EOF'
   Host github-dotfiles
     HostName github.com
     User git
     IdentityFile ~/.ssh/dotfiles_deploy
     IdentitiesOnly yes
   EOF
   chmod 600 ~/.ssh/config
   ```
4. `git clone git@github-dotfiles:<you>/dotfiles.git ~/dotfiles`
5. Copy `bin/linux-snapshot.sh` to `bin/<host>-snapshot.sh`, edit the whitelist.
6. `chmod +x ~/dotfiles/bin/<host>-snapshot.sh`
7. Test once: `~/dotfiles/bin/<host>-snapshot.sh`
8. Install cron:
   ```bash
   ( crontab -l 2>/dev/null; echo "*/15 * * * * \$HOME/dotfiles/bin/<host>-snapshot.sh >>/tmp/dotfiles-backup.out 2>>/tmp/dotfiles-backup.err" ) | crontab -
   ```

## Common ops

| Want | Do |
|---|---|
| Force a snapshot now | Run the host's `bin/<host>-snapshot.sh` |
| See recent push errors | `tail /tmp/dotfiles-backup.err` |
| Disable laptop watcher | `launchctl unload ~/Library/LaunchAgents/com.<you>.dotfiles-backup.plist` |
| Disable host cron | `crontab -e`, comment the snapshot line |
| Add a new tracked path | Edit the script's whitelist |

## What NOT to track

- Anything with a credential. Snapshot scripts use a **whitelist model** so you never accidentally pick up a `.envrc` with API keys.
- Browser profiles (cookies, sessions, cached oauth tokens).
- SSH private keys, GnuPG private keys.
- `.bash_history`, `.viminfo`, `.lesshst` — small but often contain typed secrets.
- Anything per-machine: cache dirs, sockets, lock files, pidfiles.

The included `.gitignore.template` is a defense-in-depth secondary layer in case you accidentally whitelist a sensitive file.

## Gotchas

1. **`git pull --rebase` first** — without it, host A pushes between host B's snapshot ticks → host B's push gets rejected non-fast-forward → script logs to `/tmp` and exits → commits stack up locally and never push. Fixed by `git pull --rebase --autostash` as the first step in every snapshot script.

2. **The macOS LaunchAgent runs from a clean environment.** `$PATH`, `$HOME` start minimal. Set them explicitly in the plist's `EnvironmentVariables` and re-export `PATH` inside the script.

3. **`gh auth refresh` invalidates the cached token in the launchd process tree.** If commits stop after a refresh, `launchctl unload && launchctl load` the plist.

4. **Deploy keys are repo-scoped.** Generate one per host *and* per repo — don't reuse the same key across multiple repos because GitHub rejects deploy-key reuse.
