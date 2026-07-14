# Homelab Notification Services

![License](https://badgen.net/github/license/Racerx323/homelab-notification)
![last commit](https://badgen.net/github/last-commit/Racerx323/homelab-notification)
[![Open Issues](https://badgen.net/github/open-issues/Racerx323/homelab-notification)](https://github.com/Racerx323/homelab-notification/issues?q=is%3Aissue%20state%3Aopen)
[![Pull Requests](https://badgen.net/github/prs/Racerx323/homelab-notification)](https://github.com/Racerx323/homelab-notification/pulls)
<a href="https://app.thecoderegistry.com/verify/vault/a2422c00-1258-4462-998d-c93bc5d54e4c" target="_blank" rel="noopener noreferrer">
  <img src="https://thecoderegistryprod.blob.core.windows.net/public-web/verification-badges/level-1/vault/a2422c00-1258-4462-998d-c93bc5d54e4c/default-style_1-2ff3a6964bbc.png?v=1784054836" alt="The Code Registry Verification Badge" width="150" />
</a>

A centralized repository for managing notification service configurations for my homelab. This project aims to provide ready-to-use configurations for various services, making it easier to set up and maintain notifications across different applications.

## 📖 About The Project

In a homelab environment, having a reliable notification system is crucial for monitoring services, receiving alerts, and staying informed about system health. This repository contains configurations for popular notification services that can be integrated with various applications like monitoring tools, automation scripts, and more.

The goal is to have a single source of truth for these configurations, making them easy to update, share, and deploy.

### Services Covered

Currently, this repository includes configurations for:

* **[Apprise API](../apprise-api/)**: A centralized REST API for sending notifications to 100+ notification services. Automated installation and deployment for Debian 12 on Raspberry Pi 5 with Podman. Supports rootless mode for enhanced security.
* **[Mailgun](../email/Mailgun/)**: An email automation service.
* **[SMTP2GO](../email/SMTP2GO/)**: An SMTP provider for sending emails.

## 📁 Project Structure

```text
homelab-notification/
├── apprise-api/                       # Centralized notification API server
│   ├── install-apprise-podman.sh      # Main installation script
│   ├── podman-compose.yml             # Docker Compose alternative deployment
│   ├── .gitignore                     # Git ignore patterns
│   ├── README.md                      # Project overview
│   ├── INSTALLATION.md                # Step-by-step installation guide
│   ├── CONFIGURATION.md               # Configuration & environment variables
│   ├── TROUBLESHOOTING.md             # Common issues & solutions
│   ├── ROOTLESS.md                    # Rootless Podman mode guide
│   ├── QUICK_START.md                 # 30-second quickstart
│   ├── INDEX.md                       # Documentation index
│   ├── UPDATES.md                     # Migration & changelog
│   ├── scripts/                       # Utility scripts
│   │   ├── logs.sh                    # Container log viewer
│   │   ├── health-check.sh            # API health monitoring
│   │   └── backup-config.sh           # Backup & restore tool
│   ├── examples/                      # Usage examples
│   │   ├── send-notification.sh       # API usage example
│   │   ├── notification-urls.txt      # Supported service URL patterns
│   │   └── api-examples.json          # REST endpoint documentation
│   ├── docs/                          # Additional documentation
│   ├── configs/                       # Configuration templates
│   └── tests/                         # Test files
├── email/
│   ├── Mailgun/                       # Mailgun SMTP configuration
│   └── SMTP2GO/                       # SMTP2GO provider configuration
└── docs/                              # Repository documentation
```

## 🚀 Quick Start

### For Apprise API

Apprise API provides a unified REST interface for sending notifications to 100+ services. To get started:

```bash
cd apprise-api
sudo ./install-apprise-podman.sh --systemd
curl http://localhost:8000/docs  # View API documentation
```

See [apprise-api/README.md](../apprise-api/README.md) for detailed setup and configuration.

### For Email Services

Configure your preferred email service (Mailgun or SMTP2GO) in the [`email/`](../email/) directory.

<!-- **Example Usage:**

_This section is a placeholder. You can add specific examples of how to integrate these configurations with tools like `ntfy`, `Prometheus Alertmanager`, or custom scripts._

```bash
# Example of how a user might integrate a configuration
# This is just a conceptual example
cp mailgun/config.yaml /path/to/your/application/
# Remember to replace placeholder values in the config file!
``` -->

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

As this is a project I maintain in my spare time, your help is invaluable. Please see the contributing guidelines for more information on how to get started. You can also just open an issue with the tag "enhancement".

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📜 License

Distributed under the GNU General Public License v3.0. See `LICENSE.md` for more information.

## 🛡️ Security Policy

The security of this project is a top priority. If you discover a security vulnerability, please follow the guidelines in our Security Policy to report it.
