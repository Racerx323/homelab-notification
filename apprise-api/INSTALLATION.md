# Apprise API Installation Guide

Comprehensive step-by-step installation guide for Apprise API on Debian 12 Raspberry Pi 5.

## Prerequisites

Before starting, ensure you have:

- [ ] Debian 12 running on Raspberry Pi 5
- [ ] SSH access to your Pi
- [ ] sudo privileges
- [ ] Internet connectivity
- [ ] At least 2GB free disk space

## Pre-Installation Checks

### 1. Verify System Information

```bash
# Check OS and kernel
cat /etc/os-release
uname -m  # Should show aarch64 for ARM64

# Check available disk space
df -h

# Check memory
free -h
```

**Expected Output:**

- OS: Debian 12 (bookworm)
- Architecture: aarch64 (ARM64)
- Disk: At least 2GB free
- Memory: At least 512MB available

### 2. Check for Existing Podman Installation

```bash
podman --version
```

If podman is not installed, the installation script will handle it automatically.

## Installation Steps

### Step 1: Prepare the System

```bash
# Update package lists
sudo apt-get update

# Upgrade existing packages
sudo apt-get upgrade -y

# This is optional but recommended for security
sudo apt-get dist-upgrade -y
```

### Step 2: Navigate to the Apprise Directory

```bash
cd /path/to/apprise-api
```

**Note:** When running remotely via SSH/SCP, you only need to copy the `install-apprise-podman.sh` script. The Docker image will be downloaded directly from Docker Hub.

### Step 3: Review the Installation Script

```bash
# View the script to understand what it does
cat install-apprise-podman.sh

# Check script permissions
ls -l install-apprise-podman.sh
```

### Step 4: Run the Installation Script

#### Option A: Basic Installation (Manual Management)

```bash
sudo ./install-apprise-podman.sh
```

This will:

- Download the official **caronc/apprise** Docker image from Docker Hub
- Configure Podman to run the container
- Start the container immediately
- Make it available at `http://localhost:8000`

**Requirements:**

- Internet connectivity to download the Docker image (~500MB)
- Podman installed (script will verify)
- ~2GB free disk space

**Log Output Expected:**

```text
[INFO] Starting Apprise API installation on Debian 12 for Raspberry Pi 5
[INFO] Podman version: 4.3.1
[INFO] Installing system dependencies...
[INFO] Setting up Apprise data directory: /var/lib/apprise
[INFO] Pulling Apprise API image...
[INFO] Running Apprise API container...
[INFO] Container started successfully
```

#### Option B: Production Setup with Systemd (Recommended)

```bash
sudo ./install-apprise-podman.sh --systemd
```

This will:

- Install all dependencies
- Set up a systemd service for auto-start on reboot
- Create `/etc/systemd/system/apprise-api.service`
- Display management commands

**Log Output Expected:**

```text
[INFO] Creating systemd service file: /etc/systemd/system/apprise-api.service
[INFO] Systemd service created successfully
[INFO] Enable with: systemctl enable apprise-api
[INFO] Start with: systemctl start apprise-api
```

#### Option C: Custom Configuration

```bash
# Custom port
sudo ./install-apprise-podman.sh --systemd --port 8080

# Skip SSL verification (not recommended for production)
sudo ./install-apprise-podman.sh --no-verify
```

### Step 5: Verify Installation

#### Check Container Status

```bash
# List running containers
podman ps

# Look for apprise-api in the output
# Expected: apprise-api running
```

#### Test API Connectivity

```bash
# Basic connectivity test
curl http://localhost:8000/

# Expected response: JSON with API information
```

#### View Container Logs

```bash
# Real-time logs (Ctrl+C to exit)
podman logs -f apprise-api

# Last 20 lines
podman logs --tail 20 apprise-api
```

### Step 6: Enable Systemd Service (if using --systemd)

```bash
# Enable auto-start on reboot
sudo systemctl enable apprise-api

# Verify it's enabled
sudo systemctl is-enabled apprise-api
# Expected output: enabled

# Start the service
sudo systemctl start apprise-api

# Check service status
sudo systemctl status apprise-api
```

### Step 7: Configure Network Access

If accessing from other machines on your network:

```bash
# Get Pi's IP address
hostname -I

# Test connectivity from another machine
curl http://<pi-ip>:8000/

# Access web UI
# Open browser to: http://<pi-ip>:8000/docs
```

## Systemd Service Management (Post-Installation)

If you installed with `--systemd`, manage the service with:

```bash
# Start the service
sudo systemctl start apprise-api

# Stop the service
sudo systemctl stop apprise-api

# Restart the service
sudo systemctl restart apprise-api

# Check service status
sudo systemctl status apprise-api

# View service logs
sudo journalctl -u apprise-api -f

# View last 50 lines of logs
sudo journalctl -u apprise-api -n 50

# Disable auto-start
sudo systemctl disable apprise-api
```

## Post-Installation Configuration

### 1. Access the API

**Web Interface:**

```text
http://localhost:8000/docs          # Swagger UI
http://localhost:8000/redoc         # ReDoc
http://localhost:8000               # API Root
```

**From Network:**

```text
http://<pi-ip>:8000/docs
```

### 2. Add Your First Notification Service

Use the Swagger UI or curl:

```bash
# Discord Example
curl -X POST http://localhost:8000/add/apprise \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token"
    ]
  }'

# Telegram Example
curl -X POST http://localhost:8000/add/apprise \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "tgram://bot-token/chat-id"
    ]
  }'
```

### 3. Send a Test Notification

```bash
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "body": "This is a test notification",
    "title": "Apprise API Test",
    "urls": "discord://webhook_id/webhook_token"
  }'
```

### 4. Create Configuration Tags

```bash
# Add notifications to a tag
curl -X POST http://localhost:8000/add/home-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token",
      "email://user:password@gmail.com"
    ]
  }'

# Send to tagged group
curl -X POST http://localhost:8000/notify/home-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Alert for home",
    "title": "Home Alert"
  }'
```

## Troubleshooting Installation

### Container Won't Start

```bash
# Check container logs
podman logs apprise-api

# Check system resources
podman stats apprise-api

# Try stopping and removing
podman stop apprise-api
podman rm apprise-api

# Try reinstalling
sudo ./install-apprise-podman.sh
```

### Port Already in Use

```bash
# Find process using port 8000
sudo ss -tuln | grep 8000

# or

sudo lsof -i :8000

# Stop the conflicting service or use a different port:
sudo ./install-apprise-podman.sh --port 8080
```

### Podman Not Installing

```bash
# Manual podman installation
sudo apt-get update
sudo apt-get install -y podman

# Verify installation
podman --version
```

### Image Pull Fails with Authentication Error

If you see: `denied: requested access to the resource is denied` or `unauthorized: authentication required`

```bash
# Step 1: Update CA certificates (most common fix)
sudo apt-get update
sudo apt-get install -y --reinstall ca-certificates
sudo update-ca-certificates --fresh

# Step 2: Test connectivity to Docker Hub
ping -c 1 hub.docker.com
curl -I https://hub.docker.com

# Step 3: Try manual pull
sudo podman pull caronc/apprise

# Step 4: Check Podman registry configuration
cat /etc/containers/registries.conf
```

**Note:** The installer automatically configures `/etc/containers/registries.conf` with Docker Hub and Quay.io registries to enable short-name image resolution (e.g., `podman pull caronc/apprise`). This is required for Debian 12's default Podman installation.

### General Podman Issues

```bash
# Manual podman installation
sudo apt-get update
sudo apt-get install -y podman

# Verify installation
podman --version

# Check if Podman service is running
systemctl status podman
sudo systemctl start podman

# Try manual pull
podman pull caronc/apprise
```

## Uninstallation

To completely remove Apprise API:

### Option 1: Keep Configuration

```bash
# Stop service if enabled
sudo systemctl stop apprise-api
sudo systemctl disable apprise-api

# Remove container
podman stop apprise-api
podman rm apprise-api

# Remove systemd service file
sudo rm /etc/systemd/system/apprise-api.service
sudo systemctl daemon-reload

# Configuration in /var/lib/apprise is preserved
```

### Option 2: Complete Removal

```bash
# Remove container
podman stop apprise-api
podman rm apprise-api

# Remove image
podman rmi caronc/apprise

# Remove configuration
sudo rm -rf /var/lib/apprise

# Remove systemd service
sudo rm /etc/systemd/system/apprise-api.service
sudo systemctl daemon-reload
```

## Next Steps

1. **Configure Notifications**: See [CONFIGURATION.md](CONFIGURATION.md)
2. **Troubleshoot Issues**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
3. **Explore Examples**: Check `examples/` directory
4. **Read API Documentation**: Access at `http://<pi-ip>:8000/docs`

## Getting Help

- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Review container logs: `podman logs apprise-api`
- Check Apprise documentation: <https://github.com/caronc/apprise>
- Visit Apprise wiki: <https://github.com/caronc/apprise/wiki>

---

**Installation Complete!** Your Apprise API is ready to use.
