# Apprise API Configuration Guide

Complete reference for configuring Apprise API after installation.

## Table of Contents

- [Environment Variables](#environment-variables)
- [Persistent Data Storage](#persistent-data-storage)
- [Network Configuration](#network-configuration)
- [Mailrise SMTP Relay](#mailrise-smtp-relay)
- [SSL/TLS Setup](#ssltls-setup)
- [Advanced Configuration](#advanced-configuration)
- [Notification Service Integration](#notification-service-integration)
- [API Tags and Organization](#api-tags-and-organization)

## Environment Variables

### Setting Environment Variables

#### For Systemd Service

Edit `/etc/systemd/system/apprise-api.service`:

```bash
sudo nano /etc/systemd/system/apprise-api.service
```

Add environment variables in the `[Service]` section:

```ini
[Service]
Environment="APPRISE_DEBUG=1"
Environment="APPRISE_PLUGINS_PATH=/apprise/plugins"
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

#### For Direct Podman Run

```bash
podman run -d \
  --name apprise-api \
  -p 8000:8000 \
  -e APPRISE_DEBUG=1 \
  -v /var/lib/apprise:/apprise \
  caronc/apprise
```

### Common Environment Variables

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `APPRISE_DEBUG` | `0` | Enable debug logging (0=off, 1=on) |
| `APPRISE_PLUGINS_PATH` | `/apprise` | Path to plugins directory |
| `APPRISE_STATIC_FILES_PATH` | `/apprise/static` | Path to static files |
| `APPRISE_UPLOAD_PATH` | `/apprise/upload` | Path for uploads |
| `MAX_CONTENT_LENGTH` | `2097152` | Maximum request size (2MB) |

## Persistent Data Storage

### Default Configuration

- **Mount Point**: `/var/lib/apprise`
- **Container Path**: `/apprise`
- **Permissions**: `755` (rwxr-xr-x)
- **Rootless Mount Point**: `~/.apprise`

When Mailrise is enabled:

- **System Mailrise Config**: `/etc/mailrise.conf`
- **Rootless Mailrise Config**: `~/.config/mailrise/mailrise.conf`
- **Existing Config Behavior**: existing configs are preserved; generated starter configs are written to `mailrise.conf.example`
- **Container Path**: `/etc/mailrise.conf`

### Directory Structure

```text
/var/lib/apprise/
├── urls                    # Stored notification URLs
├── tags/                   # Tag configurations
├── history/                # Notification history
└── plugins/                # Custom plugins (if any)
```

### Backup and Restore

#### Backup Configuration

```bash
#!/bin/bash
# Create dated backup
BACKUP_DIR="$HOME/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"
sudo tar czf "$BACKUP_DIR/apprise-backup-$DATE.tar.gz" \
  /var/lib/apprise

# Set permissions
sudo chown $USER:$USER "$BACKUP_DIR/apprise-backup-$DATE.tar.gz"

echo "Backup saved to: $BACKUP_DIR/apprise-backup-$DATE.tar.gz"
```

#### Restore Configuration

```bash
#!/bin/bash
# Stop the service
sudo systemctl stop apprise-api

# Restore from backup
sudo tar xzf apprise-backup-*.tar.gz -C /

# Restart service
sudo systemctl start apprise-api
```

### Change Storage Location

To use a different storage directory:

1. Create the new directory:

    ```text
    sudo mkdir -p /mnt/apprise-storage
    sudo chmod 755 /mnt/apprise-storage
    ```

2. Migrate data:

    ```text
    sudo cp -r /var/lib/apprise/* /mnt/apprise-storage/
    sudo chown -R 0:0 /mnt/apprise-storage
    ```

3. Update systemd service:

    ```text
    sudo nano /etc/systemd/system/apprise-api.service
    ```

4. Change the volume line:

    ```text
    ExecStart=podman run --rm \
    --name apprise-api \
    -p 8000:8000 \
    -v /mnt/apprise-storage:/apprise \
    caronc/apprise
    ```

5. Reload and restart:

    ```text
    sudo systemctl daemon-reload
    sudo systemctl restart apprise-api
    ```

## Network Configuration

### Access from Network

#### Find Pi's IP Address

```bash
# Get all network interfaces
hostname -I

# or using ip command
ip addr show

# or using ifconfig (if installed)
ifconfig
```

#### Test Network Connectivity

```bash
# From another machine on network
curl http://<pi-ip>:8000/notify

# From the Pi itself
curl http://localhost:8000/notify
```

### Firewall Configuration

#### If using UFW

```bash
# Allow port 8000
sudo ufw allow 8000/tcp

# Allow from specific IP only
sudo ufw allow from 192.168.1.100 to any port 8000

# Check rules
sudo ufw status
```

#### If using Firewalld

```text
# Add port
sudo firewall-cmd --permanent --add-port=8000/tcp

# Reload firewall
sudo firewall-cmd --reload

# Check rules
sudo firewall-cmd --list-all
```

### Port Configuration

Change API port:

1. Stop the service:

    ```text
    sudo systemctl stop apprise-api
    ```

2. Update systemd service:

    ```text
    sudo nano /etc/systemd/system/apprise-api.service
    ```

3. Change port mapping (e.g., 9000):

    ```text
    ExecStart=podman run --rm \
    --name apprise-api \
    -p 9000:8000 \
    -v /var/lib/apprise:/apprise \
    caronc/apprise
    ```

4. Reload and restart:

    ```text
    sudo systemctl daemon-reload
    sudo systemctl restart apprise-api
    ```

5. Verify:

    ```text
    curl http://localhost:9000/notify
    ```

### Shared Podman Network for Mailrise

When the installer runs with `--mailrise`, it creates a Podman network named `notify-network`:

```bash
podman network inspect notify-network
```

Both containers join this network so Mailrise can call Apprise API by container name:

```text
apprise://apprise-api:8000/your_apprise_config_key
```

The Apprise API container always listens on port `8000` inside the container. The `--port` option only changes the host port mapping.

## Mailrise SMTP Relay

Mailrise is optional and installed with:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

Rootless:

```bash
./install-apprise-podman.sh --rootless --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
```

### Generated Mailrise Configuration

System-wide installs write `/etc/mailrise.conf`. Rootless installs write `~/.config/mailrise/mailrise.conf`. If the config already exists, the installer leaves it unchanged and writes the generated starter config as `mailrise.conf.example` in the same directory.

Default generated config:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

Send email to `notify@mailrise.xyz` to use this config. You can edit the config name or add more configs later:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
  critical:
    urls:
      - apprise://apprise-api:8000/critical-alerts
```

Restart Mailrise after editing:

```bash
sudo systemctl restart mailrise

# Rootless
systemctl --user restart mailrise
```

### Mailrise Ports

Mailrise listens on container port `8025`. Use `--mailrise-port` to change the host port:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-port 2525 --mailrise-apprise-key your_apprise_config_key
```

Point SMTP clients at:

- Host: `<pi-ip>`
- Port: `8025` or your `--mailrise-port`
- Recipient: `notify@mailrise.xyz`

### Mailrise Service Management

```bash
sudo systemctl enable mailrise
sudo systemctl start mailrise
sudo systemctl status mailrise
sudo journalctl -u mailrise -f
```

Rootless:

```bash
systemctl --user enable mailrise
systemctl --user start mailrise
systemctl --user status mailrise
journalctl --user -u mailrise -f
```

## SSL/TLS Setup

### Option 1: Reverse Proxy with Nginx

1. Install nginx:

    ```text
    sudo apt-get install -y nginx
    ```

2. Create SSL certificate:

    ```text
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot certonly --standalone -d your-domain.com
    ```

3. Configure nginx reverse proxy:

    ```text
    sudo nano /etc/nginx/sites-available/apprise
    ```

4. Add configuration:

    ```nginx
    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;

        location / {
            proxy_pass http://localhost:8000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$host$request_uri;
    }
    ```

5. Enable site and test:

    ```text
    sudo ln -s /etc/nginx/sites-available/apprise /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx
    ```

### Option 2: Caddy Reverse Proxy

1. Install Caddy:

    ```bash
    sudo apt-get install -y caddy
    ```

2. Configure Caddyfile:

    ```bash
    sudo nano /etc/caddy/Caddyfile
    ```

    Add:

    ```text
    your-domain.com {
        reverse_proxy localhost:8000 {
            header_up X-Forwarded-For {http.request.remote}
            header_up X-Forwarded-Proto {http.request.proto}
            header_up Host {http.request.host}
        }
    }
    ```

3. Enable and restart:

    ```bash
    sudo systemctl enable caddy
    sudo systemctl restart caddy
    ```

## Advanced Configuration

### Enable Debug Logging

```bash
# Edit systemd service
sudo nano /etc/systemd/system/apprise-api.service

# Add to [Service] section:
# Environment="APPRISE_DEBUG=1"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart apprise-api

# View debug logs
sudo journalctl -u apprise-api -f
```

### Memory and CPU Limits

Limit resource usage in systemd:

```bash
sudo nano /etc/systemd/system/apprise-api.service
```

Add to `[Service]` section:

```text
# Memory limit: 512MB
MemoryLimit=512M

# CPU quota: 50% of one core
CPUQuota=50%
```

Reload and restart:

```text
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

Monitor resources:

```text
podman stats apprise-api
```

### Increase Request Size

Edit systemd service to increase max content length:

```text
Environment="MAX_CONTENT_LENGTH=10485760"  # 10MB
```

### Custom Plugins

To add custom notification plugins:

1. Create plugins directory:

    ```text
    mkdir -p /var/lib/apprise/plugins
    ```

2. Add plugin files (Python)

3. Update environment:

    ```text
    Environment="APPRISE_PLUGINS_PATH=/apprise/plugins"
    ```

4. Restart service:

    ```text
    sudo systemctl restart apprise-api
    ```

## Notification Service Integration

### Discord

```json
{
  "urls": ["discord://webhook_id/webhook_token"]
}
```

Get webhook from Discord server → Settings → Webhooks

### Telegram

```json
{
  "urls": ["tgram://bot-token/chat-id"]
}
```

Create bot with BotFather on Telegram

### Slack

```json
{
  "urls": ["slack://token-a/token-b/token-c"]
}
```

Get tokens from Slack app configuration

### Email (SMTP)

```json
{
  "urls": ["mailsmtp://user:password@smtp.gmail.com:587/?from=user@gmail.com"]
}
```

### PagerDuty

```json
{
  "urls": ["pagerduty://integration-key"]
}
```

### Webhooks (Generic)

```json
{
  "urls": ["json://your-webhook-url"]
}
```

### Multiple Services (Tag)

```bash
curl -X POST http://localhost:8000/add/alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token",
      "tgram://bot-token/chat-id",
      "slack://token-a/token-b/token-c"
    ]
  }'
```

## API Tags and Organization

### Create a Tag

```bash
curl -X POST http://localhost:8000/add/critical-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token"
    ]
  }'
```

### List All Tags

```bash
curl http://localhost:8000/urls
```

### Send to Tag

```bash
curl -X POST http://localhost:8000/notify/critical-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Critical system event detected",
    "title": "Critical Alert",
    "type": "failure"
  }'
```

### Get Tag Details

```bash
curl http://localhost:8000/details/critical-alerts
```

### Delete a URL from Tag

```bash
curl -X DELETE http://localhost:8000/remove/critical-alerts/discord://webhook_id/webhook_token
```

### Notification Types

When sending notifications, use these types for icons:

- `info` - Information (default)
- `success` - Successful action
- `warning` - Warning
- `failure` - Error/failure

Example:

```bash
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Database backup completed",
    "title": "Backup Status",
    "type": "success"
  }'
```

## Performance Tuning

### For Raspberry Pi 5

Recommended settings:

```ini
# Memory: 384MB for typical use
MemoryLimit=384M

# CPU: 75% for balanced performance
CPUQuota=75%

# Increase request timeout
Environment="TIMEOUT=30"
```

### Monitor Performance

```bash
# Real-time stats
watch podman stats apprise-api

# Check container resource limits
podman inspect apprise-api | grep -A 5 "MemoryLimit\|CpuQuota"
```

---

See [README.md](README.md) for overview and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for issues.
