# Apprise API Deployment for Raspberry Pi 5

Automated installation and deployment of [Apprise API](https://github.com/caronc/apprise) on Debian 12 running on Raspberry Pi 5 with Podman.

## Overview

**Apprise** is a powerful notification library that supports 100+ notification services. **Apprise API** is a web service that exposes Apprise functionality via REST API, allowing you to send notifications to any service through HTTP requests.

This package provides an automated installer for the **official Apprise API Docker container** running on **Podman** (Debian 12, Raspberry Pi 5). It can also install **Mailrise**, an SMTP-to-Apprise relay, so devices and applications that only know how to send email can trigger Apprise notifications.

### Key Points

- ✅ **Uses Official Docker Image**: `caronc/apprise` from Docker Hub
- ✅ **Podman Compatible**: Podman can run Docker containers natively
- ✅ **Rootless Mode**: Run without sudo using Podman's rootless container support
- ✅ **Debian 12 Ready**: Optimized for Raspberry Pi 5
- ✅ **Automated Setup**: Single script handles full installation
- ✅ **Systemd Integration**: Auto-start on boot with service management
- ✅ **Optional Mailrise Relay**: SMTP notifications through `docker.io/yoryan/mailrise:latest`

### Use Cases

- Centralized notification hub for your homelab
- Alert aggregation from multiple services
- Notification distribution across different platforms
- Integration with monitoring systems (Munin, Prometheus, etc.)
- Home automation notifications
- Custom application notifications

## System Requirements

- **OS**: Debian 12
- **Hardware**: Raspberry Pi 5 (ARM64)
- **Container Runtime**: Podman 4.3.1 or later
- **Disk Space**: ~2GB for image + persistent data
- **Memory**: ~256MB minimum (512MB recommended)
- **Network**: Port access (default: 8000)

## Quick Start

### 1. Clone/Navigate to This Directory

```bash
git clone <your-repo-url>
cd apprise-api
```

### 2. Run Installation

**System-wide (requires sudo):**

```bash
# Basic installation (manual container management)
sudo ./install-apprise-podman.sh

# With systemd service (recommended for production)
sudo ./install-apprise-podman.sh --systemd

# Custom API port
sudo ./install-apprise-podman.sh --systemd --port 8080

# Apprise API plus Mailrise SMTP relay
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

**Rootless mode (no sudo needed):**

```bash
# Basic rootless installation
./install-apprise-podman.sh --rootless

# Rootless with systemd service
./install-apprise-podman.sh --rootless --systemd

# Custom port in rootless mode
./install-apprise-podman.sh --rootless --systemd --port 8000

# Rootless Apprise API plus Mailrise
./install-apprise-podman.sh --rootless --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

The script will:

- Download the official **caronc/apprise** Docker image from Docker Hub
- Download **docker.io/yoryan/mailrise:latest** when `--mailrise` is enabled
- Configure it to run with Podman on Debian 12
- Create the `notify-network` Podman network when Mailrise is enabled
- Set up systemd service if requested (user-level for rootless, system-level for sudo)
- Make it available at <http://localhost:8000>

**For rootless mode, also enable lingering to keep the service running:**

```bash
loginctl enable-linger
```

### 3. Verify Installation

```bash
# Check container status
podman ps | grep apprise

# View logs
podman logs -f apprise-api

# Test API
curl http://localhost:8000/notify

# If Mailrise was installed
podman ps | grep mailrise
podman logs -f mailrise
```

### 4. Access Apprise API

- **API Endpoint**: `http://<pi-ip>:8000`
- **Swagger UI**: `http://<pi-ip>:8000/docs`
- **ReDoc**: `http://<pi-ip>:8000/redoc`

## Directory Structure

```text
apprise-api/
├── install-apprise-podman.sh      # Automated installation script
├── README.md                        # This file
├── QUICK_START.md                   # Fast setup guide
├── INSTALLATION.md                  # Detailed installation guide
├── CONFIGURATION.md                 # Configuration reference
├── ROOTLESS.md                      # Rootless Podman guide
├── TROUBLESHOOTING.md              # Common issues and solutions
├── INDEX.md                         # Documentation index
├── UPDATES.md                       # Change summary
├── podman-compose.yml              # Podman compose configuration
├── examples/                        # Example configurations and scripts
│   ├── send-notification.sh         # Example notification script
│   ├── api-examples.json            # API reference examples
│   └── notification-urls.txt        # Notification service URL formats
└── scripts/                         # Utility scripts
    ├── backup-config.sh             # Backup persistent data
    ├── logs.sh                      # View container logs
    └── health-check.sh              # Health check script
```

## Installation Methods

### Method 1: Automated Script (Recommended)

```bash
sudo ./install-apprise-podman.sh --systemd
```

**Advantages:**

- Fully automated setup
- Downloads official Docker image from Docker Hub
- Systemd integration for auto-start
- Dependency validation
- Health verification

**What it does:**

1. Verifies Podman installation
2. Installs dependencies (curl, wget, ca-certificates)
3. Pulls `caronc/apprise` Docker image
4. Optionally pulls `docker.io/yoryan/mailrise:latest`
5. Creates systemd service files if requested
6. Configures persistent storage at `/var/lib/apprise`
7. Creates `/etc/mailrise.conf` and `notify-network` when Mailrise is enabled
8. Preserves an existing Mailrise config and writes the generated starter config to `mailrise.conf.example`

### Method 2: Podman Compose

```bash
podman-compose -f podman-compose.yml up -d
```

**Advantages:**

- Uses official Docker image
- Easy to modify configuration
- Simple scaling

### Method 3: Manual Podman

```bash
# Pull official Docker image from Docker Hub
podman pull caronc/apprise

# Run container
podman run -d \
  --name apprise-api \
  -p 8000:8000 \
  -v /var/lib/apprise:/apprise \
  --restart=always \
  caronc/apprise
```

With Mailrise:

```bash
podman network create notify-network

podman run -d \
  --name apprise-api \
  -p 8000:8000 \
  -v /var/lib/apprise:/apprise \
  --network notify-network \
  --restart=always \
  caronc/apprise

podman run -d \
  --name mailrise \
  -p 8025:8025 \
  -v /etc/mailrise.conf:/etc/mailrise.conf:ro \
  --network notify-network \
  --restart=always \
  docker.io/yoryan/mailrise:latest
```

## How It Works

### Podman & Docker Compatibility

Podman is a drop-in replacement for Docker. It can:

- ✅ Pull and run Docker images directly
- ✅ Use Docker Hub registries natively
- ✅ Run containers without requiring a daemon
- ✅ Integrate with systemd for service management

### Official Apprise API Docker Image

The installer uses the official `caronc/apprise` image:

- ✅ Maintained by Apprise developers
- ✅ Pre-built and tested
- ✅ Includes all required dependencies
- ✅ Optimized for production use

### Data Persistence

- **Storage Location:** `/var/lib/apprise` (on host) → `/apprise` (in container)
- **Configuration Format:** Proprietary Apprise format
- **Survives Container Restarts:** Yes
- **Backup Compatible:** Yes

## Common Operations

### Start/Stop Service

```bash
# If using systemd
sudo systemctl start apprise-api
sudo systemctl stop apprise-api
sudo systemctl restart apprise-api

# If Mailrise is installed
sudo systemctl start mailrise
sudo systemctl stop mailrise
sudo systemctl restart mailrise

# If using direct podman
podman start apprise-api
podman stop apprise-api
podman start mailrise
podman stop mailrise
```

### View Logs

```bash
# Real-time logs
podman logs -f apprise-api

# Last 50 lines
podman logs --tail 50 apprise-api

# If using systemd
sudo journalctl -u apprise-api -f

# Mailrise logs
podman logs -f mailrise
sudo journalctl -u mailrise -f
```

### Send a Test Notification

```bash
# Via curl
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Test notification",
    "title": "Hello from Apprise",
    "urls": "discord://<webhook-id>/<webhook-token>"
  }'

# Via the provided script
./examples/send-notification.sh
```

### Backup Configuration

```bash
./scripts/backup-config.sh
```

### Check Health

```bash
./scripts/health-check.sh
```

## Configuration

See [CONFIGURATION.md](CONFIGURATION.md) for:

- Environment variables
- Persistent storage options
- Network configuration
- Mailrise SMTP relay configuration
- SSL/TLS setup

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for solutions to:

- Container startup issues
- API connection problems
- Memory/resource constraints
- Port conflicts
- Notification delivery failures
- Mailrise SMTP relay issues

## API Examples

### List configured URLs

```bash
curl http://localhost:8000/urls
```

### Add a notification URL

```bash
curl -X POST http://localhost:8000/add/apprise \
  -H "Content-Type: application/json" \
  -d '{
    "urls": ["discord://webhook-id/webhook-token"]
  }'
```

### Send notification to tag

```bash
curl -X POST http://localhost:8000/notify/home-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "body": "System alert",
    "title": "Alert"
  }'
```

### Get notification history

```bash
curl http://localhost:8000/history
```

See API documentation at `http://<pi-ip>:8000/docs` for full reference.

## Performance Tuning

### For Raspberry Pi 5

- **Default Settings**: Suitable for most deployments
- **Memory Limit**: Container has no hard limit (set via `--memory` if needed)
- **CPU Share**: Default allocation

### Monitor Resource Usage

```bash
podman stats apprise-api
```

## Rootless Mode

Podman's rootless mode allows running containers without root/sudo privileges:

```bash
# Install in rootless mode
./install-apprise-podman.sh --rootless --systemd

# Manage the service without sudo
systemctl --user start apprise-api
systemctl --user stop apprise-api

# Keep service running even when logged out
loginctl enable-linger
```

**Benefits:**

- ✅ No sudo required for container operations
- ✅ Better security (containers run as your user)
- ✅ Simpler setup
- ✅ Perfect for single-user systems like Raspberry Pi

See [ROOTLESS.md](ROOTLESS.md) for complete rootless mode guide.

## Security Considerations

- **Network Access**: Restrict API access via firewall rules
- **Authentication**: Consider adding reverse proxy with auth (nginx, Caddy)
- **TLS/SSL**: Use HTTPS for remote access
- **Backup**: Regular backups of `/var/lib/apprise` configuration
- **Updates**: Periodically pull latest image for security patches

## Backup and Restore

### Backup

```bash
tar czf apprise-backup-$(date +%Y%m%d).tar.gz /var/lib/apprise
```

### Restore

```bash
tar xzf apprise-backup-*.tar.gz -C /
systemctl restart apprise-api
```

## Updating Apprise

```bash
# Pull latest official image
podman pull caronc/apprise

# Restart container
podman stop apprise-api
podman rm apprise-api
./install-apprise-podman.sh  # or systemctl start apprise-api
```

If Mailrise is installed:

```bash
podman pull docker.io/yoryan/mailrise:latest
sudo systemctl restart apprise-api
sudo systemctl restart mailrise
```

## Documentation Files

- **[INSTALLATION.md](INSTALLATION.md)** - Detailed step-by-step installation
- **[CONFIGURATION.md](CONFIGURATION.md)** - Configuration options and advanced setup
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[ROOTLESS.md](ROOTLESS.md)** - Rootless Podman setup

## External Resources

- [Apprise GitHub Repository](https://github.com/caronc/apprise)
- [Apprise Supported Notifiers](https://github.com/caronc/apprise/wiki/Apprise_Notification_Services)
- [Apprise API Documentation](https://github.com/caronc/apprise-api)
- [Mailrise GitHub Repository](https://github.com/YoRyan/mailrise)
- [Podman Documentation](https://podman.io/docs)

## License

This deployment package is provided as-is. Apprise is licensed under the BSD 2-Clause License.

## Contributing

Feel free to submit improvements or report issues with the installation and deployment process.

---

**Last Updated**: July 2026  
**Tested On**: Debian 12, Raspberry Pi 5, Podman 4.3.1
