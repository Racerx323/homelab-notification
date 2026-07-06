# Rootless Podman Mode

This guide covers running Apprise API in Podman's rootless mode, which provides improved security and convenience.

## What is Rootless Mode?

Rootless Podman allows you to run containers as a regular user without requiring root/sudo privileges. This provides:

- **Better Security**: Containers run as your user, not as root
- **No Sudo Needed**: Run all container commands without `sudo`
- **Simpler Setup**: No system-wide configuration changes needed
- **Isolated**: Each user has their own container environment
- **Perfect for Raspberry Pi**: Ideal for single-user systems like Raspberry Pi

## Quick Start (Rootless)

```bash
# 1. Install podman if needed
sudo apt-get update
sudo apt-get install -y podman ca-certificates

# 2. Run the installer in rootless mode
./install-apprise-podman.sh --rootless --systemd

# 3. Enable user service to run on login
loginctl enable-linger

# 4. Start the service
systemctl --user start apprise-api

# 5. Access the API
curl http://localhost:8000
```

## System Requirements

- **Podman**: 4.0+ (rootless support is built-in)
- **User Account**: Regular (non-root) user account
- **Permissions**: Must have access to run `podman` (membership in `podman` group or similar)
- **Disk Space**: ~500MB in user's home directory

## Installation

### Basic Rootless Installation (No Systemd)

```bash
./install-apprise-podman.sh --rootless
```

This will:

1. Check if podman is installed
2. Create `~/.apprise` directory for persistent data
3. Pull the official Docker image
4. Start the container immediately
5. Display access information

### Rootless with User Systemd Service

```bash
./install-apprise-podman.sh --rootless --systemd
```

This adds:

- User-level systemd service (`~/.config/systemd/user/apprise-api.service`)
- Service will start when you log in
- Can be enabled to start automatically

### Custom Port (Rootless)

```bash
./install-apprise-podman.sh --rootless --port 9000
```

## User Systemd Service Management

### Enable Service (Start on Login)

```bash
systemctl --user enable apprise-api
systemctl --user start apprise-api
```

### Start/Stop Service

```bash
# Start
systemctl --user start apprise-api

# Stop
systemctl --user stop apprise-api

# Check status
systemctl --user status apprise-api
```

### View Logs

```bash
# Real-time logs
journalctl --user -u apprise-api -f

# Last 50 lines
journalctl --user -u apprise-api -n 50

# Today's logs
journalctl --user -u apprise-api --since today
```

### Restart Service

```bash
systemctl --user restart apprise-api
```

## Lingering (Keep Services Running When Logged Out)

By default, user services stop when you log out. To keep Apprise API running even when not logged in:

```bash
# Enable lingering for current user
loginctl enable-linger

# Check if enabled
loginctl show-user $USER

# Disable lingering (if needed)
loginctl disable-linger
```

With lingering enabled, the service runs in the background regardless of login status.

## Container Management

### Start Container Directly

```bash
podman start apprise-api
```

### Stop Container Directly

```bash
podman stop apprise-api
```

### View Running Containers

```bash
podman ps
```

### View Container Logs

```bash
podman logs -f apprise-api
```

### Remove Container

```bash
podman rm -f apprise-api
```

## Data Storage

Rootless mode stores persistent data in your home directory:

```bash
~/.apprise/          # Configuration and data directory
```

### Backup Configuration

```bash
tar -czf apprise-backup.tar.gz ~/.apprise/
```

### Restore Configuration

```bash
tar -xzf apprise-backup.tar.gz -C ~/
```

## Accessing the API

From the same machine:

```bash
# REST API base
curl http://localhost:8000

# Send notification
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "urls": ["discord://webhook_id/webhook_token"],
    "body": "Test notification"
  }'

# API documentation
curl http://localhost:8000/docs
```

From another machine (requires port forwarding or network access):

```bash
curl http://<raspberry-pi-ip>:8000
```

## Differences from Rootful Mode

| Feature | Rootless | Rootful (sudo) |
| --------- | ---------- | ----------- |
| Data Directory | `~/.apprise` | `/var/lib/apprise` |
| Systemd | User (`--user`) | System-wide |
| Privileges | User account | Root/sudo required |
| Port Binding | User ports only | All ports |
| Service Startup | User login or lingering | System boot |
| Container Owner | Your user | root |

## Advantages

✅ **Security**: Containers run as your user, not root  
✅ **Convenience**: No sudo needed for container operations  
✅ **Simplicity**: No system-wide configuration needed  
✅ **Safety**: Isolated to user account  
✅ **Standard**: Works with any Linux user account  

## Troubleshooting

### Cannot run rootless: "podman: command not found"

```bash
sudo apt-get install podman
```

### Container won't start: "permission denied"

Ensure your user is in the `podman` group:

```bash
groups $USER
sudo usermod -aG podman $USER
# Log out and back in
```

### Service won't start: "User not active"

Enable lingering:

```bash
loginctl enable-linger
```

### Cannot access API from other machines

Rootless containers can't bind to ports below 1024. For remote access, use a port above 1024:

```bash
./install-apprise-podman.sh --rootless --port 8000
# Then access from another machine:
# http://<raspberry-pi-ip>:8000
```

### Out of disk space in home directory

Check usage:

```bash
du -sh ~/.apprise/
df -h ~/.apprise/
```

Move to another location with more space if needed.

## Remote Deployment

### Deploy to Remote Raspberry Pi (Rootless)

```bash
# 1. Copy script
scp install-apprise-podman.sh pi@10.1.3.83:~/

# 2. SSH and run
ssh pi@10.1.3.83 << 'EOF'
  ~/install-apprise-podman.sh --rootless --systemd
  loginctl enable-linger
  systemctl --user start apprise-api
EOF

# 3. Verify
ssh pi@10.1.3.83 'curl http://localhost:8000'
```

### Check Remote Service

```bash
ssh pi@10.1.3.83 'systemctl --user status apprise-api'
ssh pi@10.1.3.83 'journalctl --user -u apprise-api -n 20'
```

## Switching Between Modes

### From Rootless to Rootful

1. Stop rootless service:

   ```bash
   systemctl --user stop apprise-api
   systemctl --user disable apprise-api
   ```

2. Run rootful installer:

   ```bash
   sudo ./install-apprise-podman.sh --systemd
   ```

### From Rootful to Rootless

1. Stop rootful service (as root):

   ```bash
   sudo systemctl stop apprise-api
   sudo systemctl disable apprise-api
   ```

2. Remove rootful service file (as root):

   ```bash
   sudo rm /etc/systemd/system/apprise-api.service
   sudo systemctl daemon-reload
   ```

3. Run rootless installer (as regular user):

   ```bash
   ./install-apprise-podman.sh --rootless --systemd
   ```

## See Also

- [INSTALLATION.md](INSTALLATION.md) - Full installation guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting common issues
- [README.md](README.md) - Project overview
- [Podman Rootless Documentation](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
