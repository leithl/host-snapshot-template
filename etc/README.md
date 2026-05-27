# /etc backup pattern (etckeeper)

System-level config snapshot. Pushes `/etc/` minus secrets to a private git repo, plus rebuild-kit metadata (apt manifest, kernel info, custom scripts in `/usr/local/bin/`, crontabs) into a tracked `/etc/system-snapshot/` directory.

## Read this first

> **etckeeper's default config tracks `/etc/shadow`, `/etc/gshadow`, and `/etc/ssh/ssh_host_*_key`.** The very first commit after `etckeeper init` will leak these to your remote unless `/etc/.gitignore` is in place beforehand.

The included `gitignore.secrets` is the comprehensive exclude list. **Drop it into `/etc/.gitignore` BEFORE running `etckeeper init`.** The setup steps below put it in the right order.

## How it works

`etckeeper` is a wrapper around git that:
- Records permissions / ownership metadata via a special `.etckeeper` file (regular git doesn't track these)
- Hooks into `apt`/`dpkg` so every package install/remove/upgrade triggers an auto-commit named after the operation
- Provides a `cron.daily` script that catches manual `/etc` edits overnight
- Supports a `PUSH_REMOTE` config that pushes after each commit — that's how this template gets `/etc` to GitHub continuously

The pre-commit hook in this template (`etckeeper-hooks/50-system-snapshot`) runs before every commit and dumps non-`/etc` rebuild artifacts into `/etc/system-snapshot/`:
- `apt-manual.txt` — `apt-mark showmanual` (the package manifest you'd `xargs apt install` from on rebuild)
- `kernel.txt`, `disks.txt`, `snap-list.txt`
- `usr-local-bin/` — copy of `/usr/local/bin/*` (your custom scripts)
- `root-crontab`, `<user>-crontab` — copies from `/var/spool/cron/crontabs/`
- `iptables.rules.v4`, `iptables.rules.v6` — `iptables-save` / `ip6tables-save` output. Read-back of the running ruleset (UFW chains, wg-quick PostUp adds, netfilter-persistent, ad-hoc rules). Diffable record of what actually got loaded — not a deploy artifact.

That dir lives inside `/etc/`, so etckeeper tracks it. Result: clone the repo on a fresh box and you have everything to rebuild — `/etc` plus the rebuild-kit metadata.

## What's NOT tracked (intentionally)

- Linux account hashes: `shadow`, `gshadow`, all backup variants (`shadow-`, `shadow.org`, `passwd-`, `group.org`, `subuid-`, `subgid-`, `security/opasswd`)
- SSH host private keys (`ssh/ssh_host_*_key` — public keys stay)
- Postfix relay creds (`postfix/sasl_passwd*`)
- msmtp creds (`msmtprc*`, `.msmtprc*`)
- Let's Encrypt private keys (`letsencrypt/archive/*/privkey*.pem`, `letsencrypt/keys`, `letsencrypt/accounts`)
- systemd encrypted creds (`credstore*`)
- WireGuard / OpenVPN keys
- Glob defenses: `*.key`, `*-key.pem`, `*privkey*`, `*sasl_passwd*`, `*.kdbx`

After a rebuild from this repo, you must regenerate these manually. The `restore.sh.template` prints a checklist at the end.

## Adoption

For each Linux host you want to back up. Tested on Ubuntu 22.04+ but should work on any Debian-family with etckeeper packaged.

### One-time GitHub setup
1. Create a **private** repo, e.g. `<you>/<host>-etc`.

### On the host
2. Generate a deploy key as root:
   ```bash
   sudo ssh-keygen -t ed25519 -f /root/.ssh/<host>-etc_deploy -N "" -C "<host>-etc-root"
   sudo cat /root/.ssh/<host>-etc_deploy.pub
   ```
   Paste that into GitHub Settings → Deploy keys → with **write access**.

3. Set up root SSH config:
   ```bash
   sudo bash -c 'cat >> /root/.ssh/config <<EOF
   
   Host github-<host>-etc
     HostName github.com
     User git
     IdentityFile /root/.ssh/<host>-etc_deploy
     IdentitiesOnly yes
   EOF'
   sudo chmod 600 /root/.ssh/config
   ```

4. **Critical step — gitignore BEFORE init:**
   ```bash
   sudo cp gitignore.secrets /etc/.gitignore
   ```

5. Set git identity for root (etckeeper needs this for commits):
   ```bash
   sudo git config --global user.email "root@<host>"
   sudo git config --global user.name "<host>-root"
   ```

6. Install etckeeper. **It auto-runs `etckeeper init` during install** — that's why the gitignore must already be in place:
   ```bash
   sudo apt install -y etckeeper
   ```

7. Sanity-check that nothing secret got tracked:
   ```bash
   for path in shadow shadow- gshadow gshadow- passwd- ssh/ssh_host_ed25519_key security/opasswd; do
     if sudo git -C /etc ls-files --error-unmatch "$path" >/dev/null 2>&1; then
       echo "FAIL: $path tracked"
     fi
   done
   ```
   No output = clean. Any "FAIL" line = nuke `/etc/.git` and start over (see Recovery below).

8. Configure auto-push:
   ```bash
   sudo sed -i 's|^#\?PUSH_REMOTE=.*|PUSH_REMOTE="origin"|' /etc/etckeeper/etckeeper.conf
   ```

9. Install the pre-commit hook:
   ```bash
   sudo cp etckeeper-hooks/50-system-snapshot /etc/etckeeper/pre-commit.d/
   sudo chmod +x /etc/etckeeper/pre-commit.d/50-system-snapshot
   ```
   Edit it to set the right username for the user-crontab snapshot.

10. Add the remote and push:
    ```bash
    cd /etc
    sudo git remote add origin git@github-<host>-etc:<you>/<host>-etc.git
    sudo git branch -m main || true
    sudo etckeeper commit "Initial /etc snapshot"
    sudo git push -u origin main
    ```

11. Drop in the rebuild script and a README:
    ```bash
    sudo cp restore.sh.template /etc/restore.sh   # edit placeholders for your host
    sudo chmod +x /etc/restore.sh
    sudo etckeeper commit "Add restore.sh"
    ```

## Recovery if a secret leaked

It happens. Order of operations:

1. **Delete the GitHub repo** to remove public surface. (`gh repo delete <you>/<host>-etc --yes`, requires `delete_repo` scope.)
2. **Rotate the leaked credential.** SSH host keys: `sudo rm /etc/ssh/ssh_host_*_key{,.pub} && sudo ssh-keygen -A && sudo systemctl restart ssh`. Update `~/.ssh/known_hosts` on every client. For password hashes, the leak is usually low-risk if hashes are strong, but you might rotate user passwords anyway.
3. **Nuke local etckeeper state**: `sudo rm -rf /etc/.git`.
4. **Update `/etc/.gitignore`** to cover whatever leaked.
5. **Re-create the GitHub repo, register a fresh deploy key** (the old one is still associated with the deleted repo for a grace period — generate a new one rather than reuse).
6. **Redo steps 6–10** from Adoption.
7. **Audit before push**: `sudo git -C /etc ls-files | grep -iE 'shadow|opasswd|sasl_passwd|privkey|_key$|credstore' | grep -v pam.d/`. Any output = stop, fix gitignore, redo.

## Common ops

| Want | Do |
|---|---|
| Force commit + push now | `sudo etckeeper commit "msg"` |
| Verify a path is excluded | `sudo git -C /etc check-ignore -v <relpath>` |
| Disable auto-push temporarily | Set `PUSH_REMOTE=""` in `/etc/etckeeper/etckeeper.conf` |
| Re-arm after a rebuild | See `restore.sh.template` final section |
| Rebuild a host from this repo | Clone, run `bash restore.sh` (after editing placeholders for your context) |
