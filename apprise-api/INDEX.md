# Apprise API Deployment Package

## Complete Documentation Index

Welcome! This package contains everything needed to deploy Apprise API on Debian 12 Raspberry Pi 5 with Podman.

---

## 📚 Documentation Files

### Getting Started

- **[QUICK_START.md](QUICK_START.md)** ⭐ **START HERE**
  - 5-minute setup guide
  - Immediate next steps
  - Common tasks and examples
  - Tips & tricks

### Core Documentation

- **[README.md](README.md)**
  - Complete overview of Apprise API
  - System requirements
  - Installation methods
  - Use cases and features
  - API examples

- **[INSTALLATION.md](INSTALLATION.md)**
  - Step-by-step installation guide
  - Pre-installation checks
  - Multiple installation methods
  - Systemd service setup
  - Post-installation configuration
  - Uninstallation procedures

- **[CONFIGURATION.md](CONFIGURATION.md)**
  - Environment variables
  - Persistent storage configuration
  - Network setup and firewall
  - Mailrise SMTP relay configuration
  - SSL/TLS setup with reverse proxies (Nginx, Caddy)
  - Resource limits and tuning
  - Notification service integration
  - API tag organization

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**
  - Common issues and solutions
  - Diagnostic commands
  - Container issues
  - Network problems
  - API issues
  - Notification delivery
  - Performance optimization
  - Getting help

- **[ROOTLESS.md](ROOTLESS.md)**
  - Rootless Podman installation
  - User-level systemd services
  - Rootless Mailrise setup
  - Lingering and remote deployment

---

## 🚀 Installation Script

### Main Script

- **[install-apprise-podman.sh](install-apprise-podman.sh)**
  - Automated installation and deployment
  - Podman dependency checking
  - Container image management
  - Systemd service integration
  - Optional Mailrise SMTP relay
  - Health verification

**Usage:**

```bash
sudo ./install-apprise-podman.sh --systemd

# With Mailrise
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key

# Rootless
./install-apprise-podman.sh --rootless --systemd
```

---

## 🛠️ Utility Scripts

Located in `scripts/` directory:

### [logs.sh](scripts/logs.sh)

View and monitor Apprise API logs

```bash
./scripts/logs.sh --follow          # Real-time logs
./scripts/logs.sh -e                # Errors only
./scripts/logs.sh --systemd         # Systemd journal
```

### [health-check.sh](scripts/health-check.sh)

Check health and status of Apprise API

```bash
./scripts/health-check.sh           # Quick check
./scripts/health-check.sh --verbose # Detailed info
./scripts/health-check.sh --monitor # Continuous monitoring
```

### [backup-config.sh](scripts/backup-config.sh)

Backup and restore configuration

```bash
./scripts/backup-config.sh          # Create backup
./scripts/backup-config.sh /mnt/backups  # Custom location
```

---

## 📋 Examples

Located in `examples/` directory:

### [send-notification.sh](examples/send-notification.sh)

Send notifications from command line

```bash
./examples/send-notification.sh alerts "Title" "Body text" info
./examples/send-notification.sh critical "Error" "Something failed" failure
```

### [api-examples.json](examples/api-examples.json)

- Complete API endpoint reference
- Example request/response bodies
- Curl command examples
- Workflow examples
- Integration patterns

### [notification-urls.txt](examples/notification-urls.txt)

- URL formats for 15+ notification services
- Discord, Telegram, Slack, Email, etc.
- Setup instructions for each service

---

## 🐳 Container Configuration

### [podman-compose.yml](podman-compose.yml)

Alternative deployment using podman-compose

```bash
podman-compose -f podman-compose.yml up -d
```

Includes:

- Service configuration
- Resource limits
- Health checks
- Environment variables
- Volume management

---

## 📖 Reading Guide

### For First-Time Users

1. Start with **[QUICK_START.md](QUICK_START.md)** (5 min read)
2. Run installation script
3. Send your first notification
4. Read **[README.md](README.md)** for full overview

### For Installation & Setup

1. **[INSTALLATION.md](INSTALLATION.md)** - Complete walkthrough
2. Run **[install-apprise-podman.sh](install-apprise-podman.sh)**
3. Use **[health-check.sh](scripts/health-check.sh)** to verify

### For Configuration & Customization

1. **[CONFIGURATION.md](CONFIGURATION.md)** - All options
2. **[examples/api-examples.json](examples/api-examples.json)** - API patterns
3. **[examples/notification-urls.txt](examples/notification-urls.txt)** - Service URLs

### For Troubleshooting

1. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Issue solutions
2. **[logs.sh](scripts/logs.sh)** - View error logs
3. **[health-check.sh](scripts/health-check.sh)** - Diagnose problems

---

## 🎯 Quick Reference

### Installation (2 minutes)

```bash
cd /path/to/apprise-api
sudo ./install-apprise-podman.sh --systemd
```

### Installation with Mailrise SMTP Relay

```bash
cd /path/to/apprise-api
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

### Send First Notification (1 minute)

```bash
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Hello",
    "body": "My first notification",
    "urls": "discord://webhook_id/webhook_token"
  }'
```

### Access API

- **API Root:** `http://localhost:8000`
- **Swagger UI:** `http://localhost:8000/docs`
- **ReDoc:** `http://localhost:8000/redoc`

### Common Commands

```bash
# View status
podman ps | grep apprise
podman ps | grep mailrise

# View logs
./scripts/logs.sh --follow
podman logs -f mailrise

# Health check
./scripts/health-check.sh

# Backup config
./scripts/backup-config.sh

# Send notification
./examples/send-notification.sh alerts "Title" "Body" success
```

### Systemd Management

```bash
sudo systemctl start apprise-api
sudo systemctl stop apprise-api
sudo systemctl restart apprise-api
sudo systemctl status apprise-api
sudo journalctl -u apprise-api -f

# Mailrise, if installed
sudo systemctl start mailrise
sudo systemctl stop mailrise
sudo systemctl restart mailrise
sudo systemctl status mailrise
sudo journalctl -u mailrise -f
```

---

## 📊 Directory Structure

```text
apprise-api/
├── README.md                      # Overview and features
├── QUICK_START.md                 # 5-minute setup (START HERE)
├── INSTALLATION.md                # Detailed installation
├── CONFIGURATION.md               # Configuration reference
├── TROUBLESHOOTING.md             # Common issues & solutions
├── INDEX.md                       # This file
├── install-apprise-podman.sh      # Main installation script
├── podman-compose.yml             # Docker Compose config
│
├── examples/                       # Example configurations
│   ├── send-notification.sh        # CLI notification script
│   ├── api-examples.json           # API reference with examples
│   └── notification-urls.txt       # Notification service URLs
│
└── scripts/                        # Utility scripts
    ├── logs.sh                     # View logs
    ├── health-check.sh             # Health monitoring
    └── backup-config.sh            # Backup/restore
```

---

## ✨ Key Features

✅ **Automated Installation** - Single script handles everything  
✅ **Podman 4.3.1 Compatible** - Tested on Raspberry Pi 5  
✅ **Systemd Integration** - Auto-start on boot  
✅ **Rootless Mode** - User-level services without sudo  
✅ **Mailrise SMTP Relay** - Optional email-to-Apprise bridge  
✅ **100+ Services** - Discord, Telegram, Slack, Email, etc.  
✅ **Persistent Storage** - Configuration survives restarts  
✅ **Health Monitoring** - Built-in health checks  
✅ **Comprehensive Docs** - Complete documentation included  
✅ **Example Scripts** - Copy-paste ready examples  
✅ **Backup Support** - Easy backup/restore  
✅ **Reverse Proxy Ready** - HTTPS setup included  

---

## 🔗 External Resources

- **Apprise GitHub:** <https://github.com/caronc/apprise>
- **Apprise Wiki:** <https://github.com/caronc/apprise/wiki>
- **Supported Notifiers:** <https://github.com/caronc/apprise/wiki/Apprise_Notification_Services>
- **Apprise API:** <https://github.com/caronc/apprise-api>
- **Mailrise:** <https://github.com/YoRyan/mailrise>
- **Podman Docs:** <https://podman.io/docs>

---

## 💡 Tips

- Start with **[QUICK_START.md](QUICK_START.md)** for immediate results
- Use **[health-check.sh](scripts/health-check.sh)** to verify setup
- Enable **--systemd** for production deployments
- Add **--mailrise** when SMTP-only devices need to send notifications
- Regular backups: `./scripts/backup-config.sh /backups`
- Check logs when issues occur: `./scripts/logs.sh --follow`
- Monitor performance: `./scripts/health-check.sh --monitor`

---

## 📞 Support

1. **Installation Help:** See [INSTALLATION.md](INSTALLATION.md)
2. **Configuration Questions:** See [CONFIGURATION.md](CONFIGURATION.md)
3. **Issues & Errors:** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
4. **API Questions:** See [examples/api-examples.json](examples/api-examples.json)
5. **External Help:** <https://github.com/caronc/apprise/issues>

---

## ✅ Verification Checklist

After installation, verify:

- [ ] Container running: `podman ps | grep apprise`
- [ ] Mailrise running, if installed: `podman ps | grep mailrise`
- [ ] API responsive: `curl http://localhost:8000`
- [ ] Health check: `./scripts/health-check.sh`
- [ ] Can access web UI: `http://localhost:8000/docs`
- [ ] Can send notification: `./examples/send-notification.sh ...`
- [ ] Backup works: `./scripts/backup-config.sh`

---

**Ready to get started?** → Go to [QUICK_START.md](QUICK_START.md)

**Last Updated:** July 2026  
**Tested On:** Debian 12, Raspberry Pi 5, Podman 4.3.1
