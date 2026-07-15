# Rootless Podman Mode

Run Apprise API and optional Mailrise containers as a regular user. Rootless
Podman keeps its images, containers, networks, and services separate from
root-owned Podman resources.

## Requirements

Rootless Podman does not require membership in a `podman` group. It requires:

- Podman and a rootless networking helper
- `newuidmap` and `newgidmap`, normally provided by `uidmap`
- Subordinate UID and GID ranges for the user
- A user systemd session for `--systemd` installations
- Host ports above `1024` unless the system is explicitly configured otherwise

Install the Debian packages:

```bash
sudo apt-get update
sudo apt-get install -y \
  podman \
  uidmap \
  slirp4netns \
  fuse-overlayfs \
  ca-certificates \
  curl \
  jq
```

Check the current user's subordinate ID ranges:

```bash
getent subuid "$USER"
getent subgid "$USER"
podman info
```

If either subordinate-ID lookup is empty, an administrator must allocate unique
ranges in `/etc/subuid` and `/etc/subgid`. After changing those files, stop the
user's containers and run `podman system migrate` before retrying.

## How the Installer Handles User IDs

The installer runs the Apprise container with the current UID/GID and
`--userns=keep-id`. This keeps the container process mapped to the owner of
`~/.apprise`, allowing the bind-mounted `config`, `plugin`, and `attach`
directories to remain writable without broad permissions.

Do not run a rootless installation with `sudo`.

## Direct Container Installation

Start Apprise API immediately without creating a systemd unit:

```bash
./install-apprise-podman.sh --rootless
```

With Mailrise:

```bash
./install-apprise-podman.sh \
  --rootless \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key
```

Directly managed containers use a Podman restart policy, but they are not user
systemd services.

## User Systemd Installation

Create an Apprise API user service:

```bash
./install-apprise-podman.sh --rootless --systemd
```

The installer creates `~/.config/systemd/user/apprise-api.service` but does not
enable or start it. Review and start it:

```bash
systemctl --user cat apprise-api
systemd-analyze --user verify ~/.config/systemd/user/apprise-api.service
systemctl --user enable --now apprise-api
```

Keep enabled user services running when no interactive session is active:

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

### Apprise API and Mailrise

```bash
./install-apprise-podman.sh \
  --rootless \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

systemd-analyze --user verify \
  ~/.config/systemd/user/apprise-api.service \
  ~/.config/systemd/user/mailrise.service

systemctl --user enable --now apprise-api mailrise
loginctl enable-linger "$USER"
```

This creates:

- `~/.config/systemd/user/apprise-api.service`
- `~/.config/systemd/user/mailrise.service`
- `~/.config/mailrise/mailrise.conf`
- `~/.apprise/config`, `~/.apprise/plugin`, and `~/.apprise/attach`
- The rootless Podman network `notify-network`

If `mailrise.conf` already exists, the installer preserves it and writes the
starter configuration to `mailrise.conf.example` in the same directory.

## Custom Ports

Use unprivileged host ports:

```bash
./install-apprise-podman.sh --rootless --systemd --port 9000
systemctl --user enable --now apprise-api
```

For a custom Mailrise port:

```bash
./install-apprise-podman.sh \
  --rootless \
  --systemd \
  --mailrise \
  --mailrise-port 2525 \
  --mailrise-apprise-key your_apprise_config_key

systemctl --user enable --now apprise-api mailrise
```

## Verification

```bash
podman ps
podman inspect apprise-api --format '{{.HostConfig.UsernsMode}} {{.Config.User}}'
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
systemctl --user status apprise-api
```

If Mailrise is enabled:

```bash
podman network inspect notify-network
podman port mailrise
podman logs --tail 50 mailrise
systemctl --user status mailrise
```

## Service Management

```bash
# Start, stop, and restart
systemctl --user start apprise-api mailrise
systemctl --user stop mailrise apprise-api
systemctl --user restart apprise-api mailrise

# Enable or disable startup
systemctl --user enable apprise-api mailrise
systemctl --user disable apprise-api mailrise

# Logs
journalctl --user -u apprise-api -f
journalctl --user -u mailrise -f
```

Omit Mailrise from commands when it is not installed.

## Container Management

Rootless containers must be managed by the same user that installed them:

```bash
podman ps -a
podman logs -f apprise-api
podman logs -f mailrise
podman restart apprise-api
podman restart mailrise
```

Do not use `sudo podman`; that selects root's separate container storage.

## Storage

| Purpose | Rootless path |
| -------- | ------------- |
| Apprise configuration | `~/.apprise/config` |
| Apprise plugins | `~/.apprise/plugin` |
| Apprise attachments | `~/.apprise/attach` |
| Mailrise configuration | `~/.config/mailrise/mailrise.conf` |
| User service units | `~/.config/systemd/user` |

Avoid changing these directories to `root:root`. They must remain writable by
the rootless user.

## Backup and Restore

Select rootless paths explicitly if the machine also has rootful data:

```bash
APPRISE_DATA_DIR="$HOME/.apprise" \
MAILRISE_CONFIG_FILE="$HOME/.config/mailrise/mailrise.conf" \
  ./scripts/backup-config.sh "$HOME/backups"
```

Before restoring, stop the services and verify the checksum:

```bash
systemctl --user stop mailrise apprise-api
cd "$HOME/backups"
sha256sum -c apprise-backup-YYYYMMDD_HHMMSS.tar.gz.sha256
tar xzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz -C /
systemctl --user start apprise-api mailrise
```

Omit Mailrise commands if it is not installed. Inspect archive contents with
`tar tzf ARCHIVE` before extraction when restoring onto a different host or
user account.

## Troubleshooting

### Missing Subordinate IDs

```bash
getent subuid "$USER"
getent subgid "$USER"
```

Ask an administrator to allocate unique ranges. Do not copy another user's
ranges.

### Permission Denied on Persistent Storage

```bash
ls -ld ~/.apprise ~/.apprise/config ~/.apprise/plugin ~/.apprise/attach
podman inspect apprise-api --format '{{.HostConfig.UsernsMode}} {{.Config.User}}'
```

The user namespace should be `keep-id`, and the directories should be owned by
the current user. Re-run the current installer after backing up locally modified
service units.

### Services Stop After Logout

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
systemctl --user enable --now apprise-api
```

### Mailrise Cannot Reach Apprise API

```bash
podman ps
podman network inspect notify-network
podman logs --tail 100 mailrise
cat ~/.config/mailrise/mailrise.conf
```

The Mailrise URL must use `apprise-api:8000`, not the host's published API port.

## Remote Deployment

Use placeholders rather than a hard-coded local address:

```bash
scp install-apprise-podman.sh USER@SERVER_IP:~/
ssh USER@SERVER_IP
```

On the remote host:

```bash
chmod +x ~/install-apprise-podman.sh
~/install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
curl -fsS http://localhost:8000/status
```

## Changing Between Rootless and Rootful Modes

Rootless and rootful Podman use separate storage. Back up the current data,
stop and disable its services, install the other mode, and restore or migrate
the data deliberately. Do not leave both modes enabled on the same host ports.

For example, before leaving rootless mode:

```bash
systemctl --user disable --now apprise-api mailrise
podman rm -f apprise-api mailrise
```

Preserve `~/.apprise` and `~/.config/mailrise` until the new deployment has been
verified.

## See Also

- [Installation guide](INSTALLATION.md)
- [Configuration guide](CONFIGURATION.md)
- [Troubleshooting guide](TROUBLESHOOTING.md)
- [Project overview](../README.md)
- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
