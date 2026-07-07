# Apprise API Troubleshooting Guide

Common issues, diagnostics, and solutions for Apprise API on Raspberry Pi 5.

## Table of Contents

- [Container Issues](#container-issues)
- [Network and Connectivity](#network-and-connectivity)
- [API Issues](#api-issues)
- [Notification Delivery](#notification-delivery)
- [Mailrise Issues](#mailrise-issues)
- [Performance Issues](#performance-issues)
- [Storage and Backup Issues](#storage-and-backup-issues)
- [System Integration Issues](#system-integration-issues)
- [Getting Help](#getting-help)

## Container Issues

### Short-Name Registry Resolution Error

#### Symptom

```text
Error: short-name "caronc/apprise" did not resolve to an alias and no 
unqualified-search registries are defined in "/etc/containers/registries.conf"
```

#### Cause

Debian 12's default Podman installation doesn't configure unqualified-search registries, preventing short-name image pulls.

#### Solutions

**Solution 1: Run the Installer (Automatic)**

The `install-apprise-podman.sh` script automatically configures this:

```bash
sudo ./install-apprise-podman.sh
```

The installer adds to `/etc/containers/registries.conf`:

```ini
[registries.search]
registries = ['docker.io', 'quay.io']
```

**Solution 2: Manual Configuration**

Add registry search configuration manually:

```bash
# Check current registries.conf
cat /etc/containers/registries.conf

# Add registry search section (requires sudo)
sudo tee -a /etc/containers/registries.conf << 'EOF'

[registries.search]
registries = ['docker.io', 'quay.io']
EOF

# Verify configuration
cat /etc/containers/registries.conf

# Try pull again
podman pull caronc/apprise

# Mailrise uses a fully qualified image name
podman pull docker.io/yoryan/mailrise:latest
```

**Solution 3: Use Fully Qualified Image Names**

Temporarily use fully qualified names while troubleshooting:

```bash
# Instead of: podman pull caronc/apprise
# Use:
podman pull docker.io/caronc/apprise
```

### Docker Hub Image Pull Fails (Authentication Error)

#### Symptom

```text
Error: denied: requested access to the resource is denied
unauthorized: authentication required
```

When running: `podman pull caronc/apprise`

#### Diagnosis

```bash
# Check if Docker Hub is accessible
ping -c 1 hub.docker.com
curl -I https://hub.docker.com

# Check CA certificates
ls -la /etc/ssl/certs/ca-certificates.crt
ls -la /usr/local/share/ca-certificates/

# Test curl to Docker Hub
curl -I https://hub.docker.com

# Check registry configuration
cat /etc/containers/registries.conf
```

#### Solutions

**Solution 1: Update CA Certificates (Most Common Fix)**

```bash
# Reinstall and update CA certificates
sudo apt-get update
sudo apt-get install -y --reinstall ca-certificates
sudo update-ca-certificates --fresh

# Verify update was applied
sudo update-ca-certificates -v

# Try pull again
sudo podman pull caronc/apprise
```

**Solution 2: Check Podman Installation**

```bash
# Verify Podman is installed and working
podman --version
podman info

# Try pull again
sudo podman pull caronc/apprise
```

**Solution 3: Network/Firewall Issues**

```bash
# Test basic connectivity
ping -c 1 hub.docker.com
traceroute hub.docker.com

# Check if system uses HTTP proxy
echo $http_proxy
echo $https_proxy

# Configure proxy if needed in /etc/containers/registries.conf
```

### Container Won't Start

#### Symptom

```
Container exits immediately after podman start command
```

#### Diagnosis

```bash
# Check container status
podman ps -a

# View error logs
podman logs apprise-api

# Get detailed error information
podman inspect apprise-api | grep -A 20 "State"
```

#### Solutions

```bash
# Check if image exists
podman images | grep caronc

# If missing, pull official image
podman pull caronc/apprise

# Stop and remove old container
podman stop apprise-api
podman rm apprise-api

# Restart with current image
sudo ./install-apprise-podman.sh --systemd

# Or re-run installation script
sudo ./install-apprise-podman.sh
```

**Solution 2: Check Resource Constraints**
```bash
# Check available memory
free -h

# Check disk space
df -h

# Check if running out of storage
df /var/lib/apprise
```

Required: ~1GB free disk space, ~256MB available RAM

### Installer Fails and Cleans Up

#### Symptom

```text
[ERROR] Installation failed with exit code ...
[INFO] Removed ... created by this run
```

#### Explanation

The installer has a failure trap. If an Apprise API or Mailrise install fails partway through, it removes artifacts created by that run:

- Newly-created `apprise-api` or `mailrise` containers
- Newly-created systemd service files
- Generated Mailrise config/example files
- Newly-created `notify-network`
- Empty data/config directories created by the failed run

Existing Mailrise configs, existing service files, and existing Podman networks are preserved. If a service file existed before the run, the installer backs it up before writing and restores it during cleanup.

#### Next Steps

```bash
# Review the original failure above the cleanup logs
podman ps -a
podman network ls
sudo systemctl status apprise-api
sudo systemctl status mailrise
```

**Solution 3: Clean and Restart**

```bash
# Stop container
podman stop apprise-api

# Remove container
podman rm apprise-api

# Clean up unused images/containers
podman system prune -a

# Reinstall
sudo ./install-apprise-podman.sh --systemd
```

### Container Keeps Restarting

#### Symptom

```bash
podman ps shows container with restart policy
Container keeps restarting every few seconds
```

#### Diagnosis

```bash
# View container events
podman events --filter container=apprise-api

# Check logs for crash message
podman logs --tail 50 apprise-api

# Check system resources
podman stats apprise-api
```

#### Solutions

**Solution 1: Check Memory Limits**

```bash
# If using systemd with memory limit, increase it
sudo nano /etc/systemd/system/apprise-api.service

# Change/add:
# MemoryLimit=512M

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

**Solution 2: Disable Automatic Restart (Temporary)**

```bash
# Edit systemd service
sudo nano /etc/systemd/system/apprise-api.service

# Change Restart from 'always' to 'on-failure'
# Restart=on-failure
# StartLimitBurst=3
# StartLimitIntervalSec=60

sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

**Solution 3: Check for Port Conflicts**

```bash
# Check if port 8000 is in use
sudo ss -tuln | grep 8000
sudo lsof -i :8000

# If port in use, either:
# 1. Stop conflicting service
# 2. Change Apprise port to different port (8080, 9000, etc.)
```

### Systemd Service Fails to Start

#### Symptom

```bash
systemctl start apprise-api returns error
systemctl status apprise-api shows failed
```

Use `systemctl`, not `sysctl`, for services. `sysctl enable mailrise` is a kernel-parameter command and will fail with `/proc/sys/...` errors.

#### Diagnosis

```bash
# Check service status details
sudo systemctl status -l apprise-api
sudo systemctl status -l mailrise

# View detailed journal logs
sudo journalctl -u apprise-api -n 50 -p err
sudo journalctl -u mailrise -n 50 -p err

# Validate systemd file syntax
sudo systemd-analyze verify /etc/systemd/system/apprise-api.service
sudo systemd-analyze verify /etc/systemd/system/mailrise.service
```

#### Solutions

**Solution 1: Recreate Service File**

```bash
# Backup existing service
sudo cp /etc/systemd/system/apprise-api.service \
        /etc/systemd/system/apprise-api.service.bak

# Reinstall with script
sudo ./install-apprise-podman.sh --systemd

# Enable and start
sudo systemctl enable apprise-api
sudo systemctl start apprise-api
sudo systemctl enable mailrise
sudo systemctl start mailrise
```

**Solution 2: Fix Common Syntax Errors**

```bash
sudo nano /etc/systemd/system/apprise-api.service

# Check for:
# - Proper indentation
# - Correct variable syntax (${VAR})
# - Escaped special characters
# - Valid path names

# Validate changes
sudo systemd-analyze verify /etc/systemd/system/apprise-api.service

# Reload
sudo systemctl daemon-reload
```

**Solution 3: Check Podman Availability**

```bash
# Ensure podman is available at service start time
which podman

# Check if podman service is running
systemctl status podman

# Start podman if needed
sudo systemctl start podman
```

## Network and Connectivity

### Cannot Access API from Localhost

#### Symptom

```bash
curl http://localhost:8000 returns Connection refused
telnet localhost 8000 fails
```

#### Diagnosis

```bash
# Check if container is running
podman ps | grep apprise

# Check port binding
podman port apprise-api

# Check container networking
podman inspect apprise-api --format='{{.NetworkSettings}}'

# Test from inside container
podman exec apprise-api curl localhost:8000
```

#### Solutions

**Solution 1: Verify Container Running**

```bash
# Start container if not running
podman start apprise-api

# Wait for startup
sleep 5

# Test again
curl http://localhost:8000
```

**Solution 2: Check Port Binding**

```bash
# If custom port, use correct port
curl http://localhost:8080  # for port 8080

# Check all port mappings
podman port apprise-api

# Restart with correct port
podman stop apprise-api
sudo ./install-apprise-podman.sh --port 8000
```

**Solution 3: Restart Podman**

```bash
# Restart podman daemon
sudo systemctl restart podman

# Wait a moment
sleep 3

# Start container
podman start apprise-api

# Test
curl http://localhost:8000
```

### Cannot Access API from Network

#### Symptom

```bash
curl http://<pi-ip>:8000 works locally but fails from other machine
```

#### Diagnosis

```bash
# Test connectivity from other machine
ping <pi-ip>

# Test port connectivity
nc -zv <pi-ip> 8000

# or using telnet
telnet <pi-ip> 8000

# Check firewall status on Pi
sudo ufw status
sudo firewall-cmd --list-all
```

#### Solutions

**Solution 1: Allow Firewall Access**

```bash
# For UFW
sudo ufw allow 8000/tcp
sudo ufw reload

# For Firewalld
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# Verify
sudo ufw status  # or firewall-cmd --list-all
```

**Solution 2: Verify Pi IP Address**

```bash
# Get Pi's IP
hostname -I

# Make sure using correct IP
ping <correct-ip>

# Test from other machine
curl http://<correct-ip>:8000
```

**Solution 3: Check Docker Networking**

```bash
# Ensure container is binding to all interfaces (0.0.0.0)
podman inspect apprise-api | grep -A 20 "PortBindings"

# Output should show: "0.0.0.0"

# If not, restart container or edit service file
```

### DNS Resolution Issues

#### Symptom

```bash
curl http://pi.local:8000 fails with name resolution error
```

#### Diagnosis

```bash
# Check DNS resolution
nslookup pi.local
getent hosts pi.local

# Check mDNS (Bonjour) availability
avahi-resolve -n pi.local
```

#### Solutions

**Solution 1: Use IP Address Instead**

```bash
# Instead of hostname
curl http://192.168.1.50:8000
```

**Solution 2: Configure DNS/mDNS**

```bash
# Install mDNS support
sudo apt-get install -y avahi-daemon

# Restart networking
sudo systemctl restart networking

# Try resolution again
ping pi.local
```

**Solution 3: Add to /etc/hosts**

```bash
# On accessing machine
sudo nano /etc/hosts

# Add line:
# 192.168.1.50  pi.local

# Save and try
curl http://pi.local:8000
```

## API Issues

### API Returns 500 Error

#### Symptom

```bash
curl -X POST http://localhost:8000/notify returns 500 Internal Server Error
```

#### Diagnosis

```bash
# Check container logs for error details
podman logs -f apprise-api

# Check for specific error messages
podman logs apprise-api | grep -i error

# Test basic API endpoints
curl http://localhost:8000/notify
curl http://localhost:8000/urls
```

#### Solutions

**Solution 1: Check Logs for Specific Error**

```bash
# Get detailed error
podman logs --tail 100 apprise-api | grep -i "traceback\|error"

# Common issues:
# - Invalid JSON in request
# - Missing required fields
# - File permission issues
```

**Solution 2: Validate Request JSON**

```bash
# Make sure JSON is valid
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{"body": "test", "title": "test"}'

# Test with curl -v for verbose output
curl -v -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{"body": "test", "title": "test"}'
```

**Solution 3: Check Storage Permissions**

```bash
# Verify storage directory permissions
ls -la /var/lib/apprise

# Should be accessible and writable
# Fix permissions if needed
sudo chown -R 0:0 /var/lib/apprise
sudo chmod -R 755 /var/lib/apprise
```

### API Not Responding

#### Symptom

```bash
curl times out or hangs
```

#### Diagnosis

```bash
# Check if container is responsive
podman exec apprise-api ps aux

# Check system resources
podman stats apprise-api

# Check container network
podman inspect apprise-api | grep -i "state\|network"
```

#### Solutions

**Solution 1: Restart Container**

```bash
podman restart apprise-api
sleep 5
curl http://localhost:8000
```

**Solution 2: Check Resource Usage**

```bash
# View resource stats
podman stats apprise-api

# If memory > 90%, increase limit in systemd service
sudo nano /etc/systemd/system/apprise-api.service
# Add: MemoryLimit=768M

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

**Solution 3: Increase Timeout**

```bash
# For curl
curl --max-time 30 http://localhost:8000

# Check if response comes eventually
# If very slow, may need to upgrade system or optimize config
```

## Notification Delivery

### Notifications Not Being Sent

#### Symptom

```bash
API returns success (200) but notification never arrives
```

#### Diagnosis

```bash
# Check configured URLs
curl http://localhost:8000/urls

# Get tag details
curl http://localhost:8000/details/<tag-name>

# Test with debug enabled
podman exec apprise-api apprise -d -s <service-url>

# Check notification history
curl http://localhost:8000/history
```

#### Solutions

**Solution 1: Verify Notification URL Format**

```bash
# Common formats:
# Discord: discord://webhook_id/webhook_token
# Telegram: tgram://bot-token/chat-id
# Email: mailsmtp://user:pass@smtp.server

# Validate URL with apprise CLI
podman exec apprise-api apprise -b "Test" <service-url>
```

**Solution 2: Check Network Connectivity**

```bash
# Ping notification service
ping discord.com
ping api.telegram.org

# Check DNS resolution
nslookup api.telegram.org

# If blocked, check firewall/proxy settings
```

**Solution 3: Verify Authentication**

```bash
# Ensure tokens/credentials are correct:
# - Discord webhook ID and token
# - Telegram bot token and chat ID
# - Email username and password
# - API keys for other services

# Test manually
podman exec apprise-api apprise -d -b "Test" \
  -s "discord://your-webhook-id/your-webhook-token"
```

**Solution 4: Check Notification Service Limits**

```bash
# Some services have rate limiting:
# - Discord: ~10 requests/second
# - Telegram: ~30 requests/second
# - Email: depends on provider

# If hitting limits, space out requests or increase retry delays
```

### Invalid Service URL

#### Symptom

```bash
"Invalid notification URL" error when adding service
```

#### Diagnosis

```bash
# Check URL format
# Get apprise supported services
podman exec apprise-api apprise --help

# Check URL syntax
podman logs apprise-api | grep -i "invalid\|syntax"
```

#### Solutions

**Solution 1: Verify URL Format**

```bash
# Correct format examples:
# Discord:    discord://webhook_id/webhook_token
# Telegram:   tgram://bot_token/chat_id
# Slack:      slack://token_a/token_b/token_c
# Email:      mailsmtp://user:password@smtp.server:587

# Common mistakes:
# - Missing protocol prefix
# - Malformed token/ID
# - Wrong separator characters
```

**Solution 2: Test URL with Apprise CLI**

```bash
# Test URL directly
podman exec apprise-api apprise -t "Test" -b "Body" \
  'discord://webhook_id/webhook_token'

# If error, review format
```

**Solution 3: Update to Latest Official Image**

```bash
# Get the latest official image
podman pull caronc/apprise

# Stop and remove old container
podman stop apprise-api
podman rm apprise-api

# Verify podman-compose file uses official image
# Then restart
sudo ./install-apprise-podman.sh --systemd
```

## Mailrise Issues

### Mailrise Service Does Not Exist

#### Symptom

```bash
sudo systemctl status mailrise
# Unit mailrise.service could not be found.
```

#### Solution

Install with Mailrise enabled:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
sudo systemctl enable mailrise
sudo systemctl start mailrise
```

Rootless:

```bash
./install-apprise-podman.sh --rootless --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
systemctl --user enable mailrise
systemctl --user start mailrise
```

### Mailrise Cannot Reach Apprise API

#### Symptom

Mailrise starts, but email does not trigger notifications.

#### Diagnosis

```bash
# Check both containers are running
podman ps

# Check shared network
podman network inspect notify-network
podman ps --format '{{.Names}} {{.Networks}}'

# Check Mailrise logs
podman logs --tail 100 mailrise
sudo journalctl -u mailrise -n 100
```

#### Solutions

**Solution 1: Re-run the Installer with Mailrise Enabled**

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
sudo systemctl restart mailrise
```

**Solution 2: Verify Mailrise Config**

System-wide config:

```bash
sudo cat /etc/mailrise.conf
```

Rootless config:

```bash
cat ~/.config/mailrise/mailrise.conf
```

Expected shape:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

The URL must use the container name `apprise-api` and container port `8000`, not the Raspberry Pi hostname or a custom host port.

If `/etc/mailrise.conf` or `~/.config/mailrise/mailrise.conf` already existed before running the installer, the installer does not overwrite it. Check the generated example file instead:

```bash
sudo cat /etc/mailrise.conf.example

# Rootless
cat ~/.config/mailrise/mailrise.conf.example
```

### SMTP Client Cannot Connect to Mailrise

#### Diagnosis

```bash
# Default Mailrise host port is 8025
sudo ss -tuln | grep 8025
podman port mailrise

# Check service/container status
sudo systemctl status mailrise
podman ps | grep mailrise
```

#### Solutions

Use the port configured with `--mailrise-port`. The default is `8025`:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-port 2525 --mailrise-apprise-key your_apprise_config_key
```

Point SMTP clients at:

- Host: `<pi-ip>`
- Port: `8025` or your custom `--mailrise-port`
- Recipient: `notify@mailrise.xyz`

## Performance Issues

### Slow API Response Times

#### Symptom

```bash
API requests take >5 seconds to respond
```

#### Diagnosis

```bash
# Check response time
time curl http://localhost:8000/notify

# Monitor system resources
watch podman stats apprise-api

# Check container logs for slow operations
podman logs -f apprise-api
```

#### Solutions

**Solution 1: Increase Resource Allocation**

```bash
# Edit systemd service
sudo nano /etc/systemd/system/apprise-api.service

# Increase memory and CPU
MemoryLimit=768M
CPUQuota=100%

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

**Solution 2: Reduce Number of Notifications**

```bash
# Large number of notifications slows API
# Check configured URLs
curl http://localhost:8000/urls

# Remove unused notifications
curl -X DELETE http://localhost:8000/remove/<tag>/<url>
```

**Solution 3: Enable Caching**

```bash
# Check if notifications are being sent repeatedly
# Cache successful sends to avoid redundant API calls
```

### High Memory Usage

#### Symptom

```bash
podman stats shows memory > 80% of limit
```

#### Diagnosis

```bash
# Check memory limit and usage
podman inspect apprise-api | grep -i memory

# Check for memory leaks
podman stats apprise-api --stream

# Check for large notification backlogs
curl http://localhost:8000/history | wc -l
```

#### Solutions

**Solution 1: Increase Memory Limit**

```bash
sudo nano /etc/systemd/system/apprise-api.service

# Increase MemoryLimit
MemoryLimit=512M  # or higher

sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

**Solution 2: Clear History**

```bash
# History is stored in persistent volume
# Remove old history to free space
sudo rm /var/lib/apprise/history/*

# Restart container
podman restart apprise-api
```

**Solution 3: Monitor and Report Memory Leaks**

```bash
# If memory grows continuously over time, may be a bug
# Check Apprise GitHub issues:
# https://github.com/caronc/apprise-api/issues

# Capture memory usage over time
for i in {1..10}; do
  echo "$(date): $(podman stats apprise-api --no-stream | tail -1)"
  sleep 60
done
```

## Storage and Backup Issues

### Configuration Lost After Restart

#### Symptom

```bash
Notification URLs/tags disappear after container restart
```

#### Diagnosis

```bash
# Check if storage is mounted
podman inspect apprise-api | grep -A 10 "Mounts"

# Verify storage directory exists
ls -la /var/lib/apprise

# Check stored configuration files
ls -la /var/lib/apprise/urls/
```

#### Solutions

**Solution 1: Verify Volume Mount**

```bash
# Check systemd service
sudo cat /etc/systemd/system/apprise-api.service | grep -i volume

# Should show: -v /var/lib/apprise:/apprise

# If missing, edit service and restart
sudo nano /etc/systemd/system/apprise-api.service
```

**Solution 2: Restore from Backup**

```bash
# If backup exists
sudo tar xzf apprise-backup-*.tar.gz -C /

# Restart
podman restart apprise-api
```

**Solution 3: Reconfigure After Loss**

```bash
# Recreate tags/URLs
curl -X POST http://localhost:8000/add/my-alerts \
  -H "Content-Type: application/json" \
  -d '{"urls": ["discord://webhook/token"]}'

# Export for future use
curl http://localhost:8000/urls > urls-backup.json
```

### Insufficient Disk Space

#### Symptom

```bash
"No space left on device" errors in logs
```

#### Diagnosis

```bash
# Check disk usage
df -h /var/lib/apprise

# Check what's using space
du -sh /var/lib/apprise/*

# Check overall disk
df -h /
```

#### Solutions

**Solution 1: Clear Old History**

```bash
# Remove old notification history
sudo find /var/lib/apprise/history -mtime +30 -delete

# Or completely clear history
sudo rm -rf /var/lib/apprise/history/*

# Restart
podman restart apprise-api
```

**Solution 2: Move Storage to Larger Disk**

```bash
# See CONFIGURATION.md "Change Storage Location" section
```

**Solution 3: Expand Root Filesystem**

```bash
# For Raspberry Pi with microSD card
sudo raspi-config
# Select: Advanced Options > Expand Filesystem

# Reboot
sudo reboot
```

## System Integration Issues

### Systemd Service Not Auto-Starting

#### Symptom

```bash
After reboot, apprise-api service not running
systemctl is-enabled apprise-api returns disabled
```

#### Diagnosis

```bash
# Check if service is enabled
sudo systemctl is-enabled apprise-api

# Check service file exists
ls -l /etc/systemd/system/apprise-api.service

# Check for startup failures
sudo journalctl -u apprise-api --boot
```

#### Solutions

**Solution 1: Enable Service**

```bash
# Enable auto-start
sudo systemctl enable apprise-api

# Verify
sudo systemctl is-enabled apprise-api

# Check startup sequence
sudo systemctl list-units --type service | grep apprise
```

**Solution 2: Check Dependencies**

```bash
# View service dependencies
sudo systemctl cat apprise-api | grep -i after

# Common dependencies: network.target, podman.service
# Ensure these are available at startup

# Check if podman is enabled
sudo systemctl is-enabled podman
```

**Solution 3: Fix Boot Timing Issues**

```bash
# If service tries to start before dependencies ready
sudo nano /etc/systemd/system/apprise-api.service

# Update [Unit] section:
# After=network-online.target podman.service
# Wants=network-online.target podman.service

# Add delay in [Service] section:
# ExecStartPre=/bin/sleep 5

sudo systemctl daemon-reload
sudo systemctl enable apprise-api
```

## Getting Help

### Collect Debug Information

When reporting issues, gather this information:

```bash
# System info
uname -a
cat /etc/os-release

# Podman info
podman --version
podman info

# Container status
podman ps -a
podman inspect apprise-api
podman inspect mailrise

# Recent logs
podman logs --tail 100 apprise-api
podman logs --tail 100 mailrise

# System resources
free -h
df -h
podman stats apprise-api

# Service status (if using systemd)
sudo systemctl status apprise-api
sudo systemctl status mailrise
sudo journalctl -u apprise-api -n 50
sudo journalctl -u mailrise -n 50

# Mailrise config and network, if installed
sudo cat /etc/mailrise.conf
podman network inspect notify-network
```

### Report Issues

- **Script Issues**: Check GitHub repo or create issue
- **Apprise Issues**: <https://github.com/caronc/apprise/issues>
- **Apprise API Issues**: <https://github.com/caronc/apprise-api/issues>

### Additional Resources

- [README.md](README.md) - Overview and quick start
- [INSTALLATION.md](INSTALLATION.md) - Installation guide
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration options
- [Apprise Wiki](https://github.com/caronc/apprise/wiki)
- [Podman Documentation](https://podman.io/docs)

---

**Still having issues?** Refer to Apprise documentation or create detailed bug report with debug information above.
