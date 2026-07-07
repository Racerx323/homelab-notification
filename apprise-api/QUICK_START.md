# Apprise API - Quick Start Guide

Get Apprise API up and running in 5 minutes!

## Prerequisites

- Debian 12 on Raspberry Pi 5
- SSH access with sudo privileges
- ~2GB free disk space

## Installation (2 minutes)

```bash
# Navigate to the apprise-api directory
cd /path/to/apprise-api

# Run installation (choose one)

# Option 1: Development (manual management)
sudo ./install-apprise-podman.sh

# Option 2: Production (with systemd auto-start) ⭐ RECOMMENDED
sudo ./install-apprise-podman.sh --systemd

# Option 3: Production with Mailrise SMTP relay
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key

# Rootless production with Mailrise
./install-apprise-podman.sh --rootless --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

Mailrise listens on SMTP port `8025` by default and sends to `apprise://apprise-api:8000/your_apprise_config_key` inside the shared `notify-network` Podman network.

## Verification (1 minute)

```bash
# Check if container is running
podman ps | grep apprise

# Test API connectivity
curl http://localhost:8000/

# View logs
podman logs apprise-api

# Check systemd status (if installed with --systemd)
sudo systemctl status apprise-api

# If Mailrise was installed
sudo systemctl status mailrise
podman logs mailrise
```

## First Notification (2 minutes)

### Step 1: Get a Webhook URL

Choose your notification service:

**Discord** (easiest):

1. Go to your Discord server
2. Server Settings → Integrations → Webhooks
3. Create webhook, copy the webhook URL
4. Extract: `discord://webhook_id/webhook_token`

**Telegram**:

1. Message @BotFather on Telegram to create a bot (get token)
2. Message @userinfobot to get your chat ID
3. URL: `tgram://bot_token/chat_id`

**Email**:

- Gmail: `mailsmtp://email:password@smtp.gmail.com:587/?from=email@gmail.com`
- Outlook: `mailsmtp://email:password@smtp.office365.com:587/?from=email@outlook.com`

More services: See [examples/notification-urls.txt](examples/notification-urls.txt)

### Step 2: Send Test Notification

```bash
# Using curl
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Hello Apprise",
    "body": "My first notification!",
    "urls": "discord://webhook_id/webhook_token"
  }'

# Or use the provided script
cd examples
./send-notification.sh apprise "Hello" "My first notification!" info
```

If notification arrives, you're all set! ✅

## Create Your First Tag

A "tag" is a group of notification services. Send to the tag instead of individual URLs:

```bash
# Add a tag with your notification service
curl -X POST http://localhost:8000/add/home-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": ["discord://webhook_id/webhook_token"]
  }'

# Send notification to the tag
curl -X POST http://localhost:8000/notify/home-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Disk Alert",
    "body": "Root partition is 95% full",
    "type": "failure"
  }'
```

## Common Tasks

### View All Configured Tags

```bash
curl http://localhost:8000/urls | jq .
```

### Access Web UI

Open browser to one of:

- `http://localhost:8000/docs` (Swagger)
- `http://localhost:8000/redoc` (ReDoc)
- `http://localhost:8000` (JSON API)

### From Network (Other Machine)

```bash
# Find Pi's IP
hostname -I

# Access from other machine
curl http://<pi-ip>:8000/
```

### View Logs

```bash
# Real-time logs
podman logs -f apprise-api

# Or use the provided script
./scripts/logs.sh --follow

# Systemd logs
sudo journalctl -u apprise-api -f

# Mailrise logs, if installed
podman logs -f mailrise
sudo journalctl -u mailrise -f
```

### Use Mailrise SMTP Relay

After installing with `--mailrise`, point SMTP-only devices or applications at:

- Host: `<pi-ip>`
- Port: `8025`
- Recipient: `notify@mailrise.xyz`

Mailrise uses `/etc/mailrise.conf` in system mode or `~/.config/mailrise/mailrise.conf` in rootless mode. The default generated config sends mail for `notify` to the Apprise API container:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

### Monitor Health

```bash
# Quick health check
./scripts/health-check.sh

# Continuous monitoring
./scripts/health-check.sh --monitor
```

### Backup Configuration

```bash
# Create backup
./scripts/backup-config.sh

# Restore from backup
sudo tar xzf apprise-backup-*.tar.gz -C /
podman restart apprise-api
```

## Next Steps

### 1. Configure Multiple Services

Add multiple notification channels to a tag:

```bash
curl -X POST http://localhost:8000/add/critical-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token",
      "tgram://bot_token/chat_id",
      "slack://token_a/token_b/token_c"
    ]
  }'
```

### 2. Integrate with Monitoring

Send alerts from Munin, Prometheus, or custom scripts:

```bash
# Example: From a cron job
0 * * * * curl -X POST http://localhost:8000/notify/daily-digest \
  -d "title=Daily%20Report&body=Check%20complete"
```

### 3. Set Up Reverse Proxy (for HTTPS)

See [CONFIGURATION.md](CONFIGURATION.md#ssltls-setup)

### 4. Access from Network

Configure firewall:

```bash
sudo ufw allow 8000/tcp
sudo ufw reload
```

Then access from other machines: `http://<pi-ip>:8000`

## Documentation

- **[README.md](README.md)** - Full overview and features
- **[INSTALLATION.md](INSTALLATION.md)** - Detailed installation steps
- **[CONFIGURATION.md](CONFIGURATION.md)** - Advanced configuration
- **[ROOTLESS.md](ROOTLESS.md)** - Rootless Podman setup
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and fixes
- **[examples/](examples/)** - API examples and scripts
- **[scripts/](scripts/)** - Utility scripts

## API Quick Reference

| Method | Endpoint | Purpose |
| -------- | ---------- | --------- |
| `GET` | `/urls` | List all tags |
| `POST` | `/add/{tag}` | Add notification URLs |
| `POST` | `/notify/{tag}` | Send notification |
| `GET` | `/details/{tag}` | Get tag details |
| `DELETE` | `/remove/{tag}` | Remove tag |
| `GET` | `/history` | View history |
| `GET` | `/docs` | API documentation |

Full reference: [examples/api-examples.json](examples/api-examples.json)

## Support

- 📖 See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- 🔍 Check logs: `podman logs apprise-api`
- 💬 Apprise documentation: <https://github.com/caronc/apprise/wiki>
- 🐛 GitHub Issues: <https://github.com/caronc/apprise/issues>

## Tips & Tricks

**Notification Types for Icons:**

```bash
# Green checkmark
"type": "success"

# Blue info icon
"type": "info"

# Yellow warning
"type": "warning"

# Red error
"type": "failure"
```

**Quick Test from CLI:**

```bash
./examples/send-notification.sh alerts "Test" "Body text" success
```

**Continuous Health Monitoring:**

```bash
./scripts/health-check.sh --monitor
```

**Automated Backups:**

```bash
# Add to crontab for daily backups
0 2 * * * /path/to/apprise-api/scripts/backup-config.sh /mnt/backups
```

---

**You're ready!** 🚀 Start sending notifications to your Apprise API.

For more details, see [README.md](README.md) or visit [https://github.com/caronc/apprise](https://github.com/caronc/apprise)
