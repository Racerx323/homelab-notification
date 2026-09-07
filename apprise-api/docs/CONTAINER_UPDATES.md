# Container Update Runbook

Use this runbook to update the rootful systemd-managed Apprise API and Mailrise
containers on J1-SVMF. This is a two-host procedure:

- Use the WSL operator workstation to review repository changes and release
  notes.
- Run every Podman, systemd, comparator, preflight, update, and validation
  command on `svmf.local.theama.co`.

The production host uses reviewed lifecycle helpers installed under
`/usr/local/libexec/apprise-api`; it does not need a repository checkout.
Fresh hosts receive these helpers from `install-apprise-podman.sh --production`.
Existing deployments may require the separately reviewed lifecycle retrofit
documented in the production lifecycle guide.

> [!IMPORTANT]
> Every image digest is a point-in-time input. Always run the comparator again
> immediately before an update. Never copy an old digest from accepted-live
> history.

## Understand the SHA-256 values

| Value | Purpose | Update argument? |
| ----- | ------- | ---------------- |
| Deployment bundle SHA-256 | Identifies reviewed scripts or units | No |
| Running image ID | Identifies the currently deployed local image | No |
| Registry platform digest | Identifies the exact candidate image | Yes |

The updater accepts only current, exact platform digests in the form
`sha256:` followed by 64 lowercase hexadecimal characters. It does not accept
an image tag or manifest-list digest.

## Before every update

1. From the WSL operator workstation, open an interactive session on the
   production host using its confirmed administrative account:

   ```bash
   ssh pi@svmf.local.theama.co
   ```

2. On J1-SVMF, confirm the host and required reviewed helpers before inspecting
   production. The loop prints one result for each helper; unlike a bare
   `test -x` command, it does not rely on an invisible exit status:

   ```bash
   hostname --fqdn

   for helper in \
     /usr/local/libexec/apprise-api/check-container-updates.sh \
     /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
   do
     if sudo test -x "$helper"; then
       printf 'PASS: installed and executable: %s\n' "$helper"
     else
       printf 'FAIL: missing or not executable: %s\n' "$helper" >&2
     fi
   done
   ```

   Require the hostname to identify `svmf.local.theama.co` and require two
   `PASS` lines. Any `FAIL` means stop. Installing or replacing a helper is a
   separate, reviewed host deployment; it is not part of the container update
   transaction. Use the [production lifecycle installation procedure](CONTAINER_LIFECYCLE.md#install-the-timer)
   to establish the complete helper set before continuing.

   Record ownership, mode, and checksum evidence:

   ```bash
   sudo stat -c '%a %U:%G %n' \
     /usr/local/libexec/apprise-api/check-container-updates.sh \
     /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
   sudo sha256sum \
     /usr/local/libexec/apprise-api/check-container-updates.sh \
     /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
   ```

   Require `755 root:root` for both files. Compare each checksum with its
   reviewed deployment artifact; an unexpected checksum means stop.

3. Still on J1-SVMF, compare the running images with the registry:

   ```bash
   sudo /usr/local/libexec/apprise-api/check-container-updates.sh
   ```

   Exit `0` means both images are current. Exit `10` means one or more updates
   are available. Any other nonzero exit means stop and diagnose the check.

4. Copy the `REMOTE_PLATFORM_DIGEST` only for each row marked
   `update-available`.

5. On the WSL operator workstation, review the corresponding upstream release
   notes and image provenance. Return to the existing J1-SVMF session only
   after accepting the candidate digest.

6. On J1-SVMF, choose a new backup directory that does not already exist. Use
   the date and affected applications in its name.

The preflight and update commands use the same backup path. Preflight verifies
that the path is unused but does not create it.

## Scenario 1: update Apprise API only

Set the digest printed for `apprise-api` and a new backup path:

```bash
APPRISE_DIGEST='sha256:PASTE_CURRENT_REVIEWED_APPRISE_DIGEST'
APPRISE_BACKUP='/var/backups/apprise-container-update/YYYY-MM-DD-apprise'
```

Run the non-mutating preflight:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --preflight-only \
  --backup-dir "$APPRISE_BACKUP" \
  --apprise-digest "$APPRISE_DIGEST"
```

If preflight succeeds, run the update with the identical digest and path:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --backup-dir "$APPRISE_BACKUP" \
  --apprise-digest "$APPRISE_DIGEST"
```

Do not add `--mailrise-digest` when Mailrise is not being updated.

## Scenario 2: update Mailrise only

Set the digest printed for `mailrise` and a new backup path:

```bash
MAILRISE_DIGEST='sha256:PASTE_CURRENT_REVIEWED_MAILRISE_DIGEST'
MAILRISE_BACKUP='/var/backups/apprise-container-update/YYYY-MM-DD-mailrise'
```

Run the non-mutating preflight:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --preflight-only \
  --backup-dir "$MAILRISE_BACKUP" \
  --mailrise-digest "$MAILRISE_DIGEST"
```

If preflight succeeds, run the update with the identical digest and path:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --backup-dir "$MAILRISE_BACKUP" \
  --mailrise-digest "$MAILRISE_DIGEST"
```

Do not add `--apprise-digest` when Apprise API is not being updated.

## Scenario 3: update both containers

When both rows are marked `update-available`, review both candidates and update
them in one transaction:

```bash
APPRISE_DIGEST='sha256:PASTE_CURRENT_REVIEWED_APPRISE_DIGEST'
MAILRISE_DIGEST='sha256:PASTE_CURRENT_REVIEWED_MAILRISE_DIGEST'
STACK_BACKUP='/var/backups/apprise-container-update/YYYY-MM-DD-apprise-mailrise'
```

Run the non-mutating preflight:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --preflight-only \
  --backup-dir "$STACK_BACKUP" \
  --apprise-digest "$APPRISE_DIGEST" \
  --mailrise-digest "$MAILRISE_DIGEST"
```

If preflight succeeds, run the combined update:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --backup-dir "$STACK_BACKUP" \
  --apprise-digest "$APPRISE_DIGEST" \
  --mailrise-digest "$MAILRISE_DIGEST"
```

The combined operation creates one stopped-state snapshot and one rollback
boundary for both images.

## What the updater changes

The updater pulls only the requested repository-and-digest references. It then
stops Mailrise followed by Apprise API, snapshots application data and
configuration, moves only the requested local tags, and starts Apprise API
followed by Mailrise.

Both services are briefly stopped and restarted even when only one image is
updated. This preserves dependency order and verifies the two-service stack as
one production unit.

An error after mutation begins triggers automatic rollback to both prior image
IDs and the stopped-state Apprise snapshot. Exit `125` means rollback could not
be proven and requires manual intervention. Do not delete the backup or prior
images during the observation period.

## Validate every accepted update

```bash
sudo systemctl is-active apprise-api mailrise
sudo systemctl is-enabled apprise-api mailrise
curl -fsS http://127.0.0.1:8000/status
sudo podman inspect apprise-api mailrise \
  --format '{{.Name}} {{.Image}} {{.State.Status}}'
sudo podman port mailrise 8025/tcp
sudo journalctl -u apprise-api -u mailrise --since '10 minutes ago' --no-pager
sudo /usr/local/libexec/apprise-api/check-container-updates.sh
```

The final comparator must exit `0`. Reconcile the scheduled notification state
and send the recovery notification:

```bash
sudo systemctl start apprise-container-update-check.service
sudo systemctl show apprise-container-update-check.service \
  --property=Result,ExecMainStatus
```

Require `Result=success` and `ExecMainStatus=0`. Retain the transaction backup
and prior images until the selected observation period has passed.

After accepting an image change, update its platform digest in
[`configs/svmf-production.env`](../configs/svmf-production.env) and commit that
desired-state change with the lifecycle evidence. This keeps a future
fresh-host installation aligned with the accepted production images. Do not
change the other application's digest when it was not updated.

## Related documentation

- [Production container lifecycle](CONTAINER_LIFECYCLE.md)
- [Installation guide](INSTALLATION.md)
- [Troubleshooting guide](TROUBLESHOOTING.md)
