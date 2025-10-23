# Configuration Templates

This directory contains production-ready configuration templates for the Multi-Tenant CDN system. All templates use variable substitution and must be processed during installation.

## 📁 Template Files

| File | Description | Destination |
|------|-------------|-------------|
| `config.env.template` | Main system configuration | `/etc/cdn/config.env` |
| `gitea-app.ini.template` | Gitea application settings | `/home/git/gitea/custom/conf/app.ini` |
| `msmtprc.template` | SMTP email relay configuration | `/etc/msmtprc` |
| `nginx-cdn.conf.template` | Nginx CDN server configuration | `/etc/nginx/sites-available/cdn.conf` |
| `nginx-gitea.conf.template` | Nginx Gitea reverse proxy | `/etc/nginx/sites-available/gitea.conf` |
| `cdn-autocommit@.service.template` | Systemd per-tenant auto-commit | `/etc/systemd/system/cdn-autocommit@.service` |
| `cdn-quota-monitor@.service.template` | Systemd per-tenant quota monitor | `/etc/systemd/system/cdn-quota-monitor@.service` |

## 🚀 Quick Start

### 1. Copy Templates to Installation Location

```bash
# Create template directory
sudo mkdir -p /opt/scripts/cdn/templates

# Copy all templates
sudo cp templates/*.template /opt/scripts/cdn/templates/
sudo cp templates/nginx/*.template /opt/scripts/cdn/templates/nginx/
sudo cp templates/systemd/*.template /opt/scripts/cdn/templates/systemd/

# Set permissions
sudo chmod 644 /opt/scripts/cdn/templates/*.template
sudo chmod 644 /opt/scripts/cdn/templates/nginx/*.template
sudo chmod 644 /opt/scripts/cdn/templates/systemd/*.template
```

### 2. Run Installation Script

The installation script (`cdn-install.sh`) will:
- Prompt for required values (domains, SMTP credentials, etc.)
- Generate secure tokens for Gitea
- Perform variable substitution on all templates
- Install files to their destination locations
- Set appropriate permissions
- Reload services

```bash
sudo /opt/scripts/cdn/cdn-install.sh
```

## 📋 Configuration Variables Reference

### System Configuration (config.env.template)

#### Domains
- `CDN_DOMAIN` - Primary CDN domain (e.g., cdn.example.com)
- `GITEA_DOMAIN` - Gitea web interface domain (e.g., git.example.com)

#### Network
- `SFTP_PORT` - SFTP server port (default: 2222)
- `GITEA_PORT` - Gitea HTTP port for reverse proxy (default: 3000)

#### Directories
- `BASE_DIR` - Base directory for all CDN data (default: /srv/cdn)
- `SFTP_DIR` - SFTP upload directories (default: /srv/cdn/sftp)
- `GIT_DIR` - Git repositories (default: /srv/cdn/git)
- `NGINX_DIR` - Nginx web content (default: /srv/cdn/www)
- `BACKUP_DIR` - Backup storage (default: /srv/cdn/backups)
- `LOG_DIR` - System logs (default: /var/log/cdn)

#### SMTP Configuration
- `SMTP_ENABLED` - Enable email notifications (true/false)
- `SMTP_HOST` - SMTP server hostname (e.g., smtp.gmail.com)
- `SMTP_PORT` - SMTP server port (587 for STARTTLS, 465 for TLS)
- `SMTP_AUTH` - Authentication method (plain, login, cram-md5)
- `SMTP_TLS` - TLS mode (on, starttls, off)
- `SMTP_USER` - SMTP username (usually email address)
- `SMTP_PASS` - SMTP password or app-specific password
- `SMTP_FROM` - Email FROM address for notifications
- `ALERT_EMAIL` - Administrator email for alerts

#### SSL/TLS
- `LE_EMAIL` - Let's Encrypt notification email
- `LE_ENVIRONMENT` - Always "production"

#### Gitea
- `GITEA_VERSION` - Gitea version to install (default: 1.24.6)
- `GITEA_ADMIN_USER` - Admin username (default: cdnadmin)
- `GITEA_ADMIN_EMAIL` - Admin email
- `GITEA_ADMIN_PASS` - Admin password (change immediately!)
- `GITEA_SECRET_KEY` - Generated during installation
- `GITEA_INTERNAL_TOKEN` - Generated during installation
- `GITEA_JWT_SECRET` - Generated during installation

#### Nginx Cache
- `CACHE_SIZE` - Maximum cache size (default: 10g)
- `CACHE_INACTIVE` - Remove unused cache after (default: 30d)

#### Quota Management
- `DEFAULT_QUOTA_MB` - Default quota for new tenants (default: 5120 MB)
- `QUOTA_WARN_THRESHOLD_1` - First warning threshold (default: 70%)
- `QUOTA_WARN_THRESHOLD_2` - Second warning threshold (default: 80%)
- `QUOTA_WARN_THRESHOLD_3` - Critical threshold (default: 90%)
- `QUOTA_CHECK_INTERVAL` - Real-time check interval (default: 30s)
- `QUOTA_ENFORCEMENT` - Action on limit (block, alert, none)

#### Git Configuration
- `GIT_DEFAULT_BRANCH` - Default branch name (default: main)
- `AUTOCOMMIT_DELAY` - Delay after last change (default: 60s)
- `GIT_COMMIT_PREFIX` - Auto-commit prefix (default: [AUTO])

#### Backups
- `BACKUP_RETENTION_DAYS` - Keep backups for days (default: 30)
- `BACKUP_COMPRESS` - Enable compression (default: true)

## 🔐 Security Tokens

Gitea requires three secure random tokens. These should be generated during installation:

```bash
# Generate SECRET_KEY (64 characters)
gitea generate secret SECRET_KEY

# Generate INTERNAL_TOKEN (longer token)
gitea generate secret INTERNAL_TOKEN

# Generate JWT_SECRET (43 characters base64)
gitea generate secret JWT_SECRET
```

The installation script generates these automatically if Gitea is available, or uses OpenSSL as a fallback.

## 📧 SMTP Configuration Examples

### Gmail with App Password

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_AUTH=plain
SMTP_TLS=starttls
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-16-char-app-password
```

**Gmail Setup:**
1. Enable 2-factor authentication
2. Generate App Password: https://myaccount.google.com/apppasswords
3. Use the 16-character App Password (not your regular password)

### Office365

```bash
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_AUTH=login
SMTP_TLS=starttls
SMTP_USER=your-email@yourdomain.com
SMTP_PASS=your-password
```

### SendGrid

```bash
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_AUTH=plain
SMTP_TLS=starttls
SMTP_USER=apikey
SMTP_PASS=YOUR_SENDGRID_API_KEY
```

### AWS SES

```bash
SMTP_HOST=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_AUTH=plain
SMTP_TLS=starttls
SMTP_USER=YOUR_SMTP_USERNAME
SMTP_PASS=YOUR_SMTP_PASSWORD
```

## 🔧 Manual Template Processing

If you need to process templates manually:

```bash
# Process a single template
envsubst < templates/config.env.template > /etc/cdn/config.env

# Process all templates
for template in templates/*.template; do
  output="${template%.template}"
  envsubst < "$template" > "$output"
done
```

## 🏗️ Directory Structure After Installation

```
/srv/cdn/
├── sftp/           # SFTP upload directories (chroot jails)
│   └── tenant-name/
├── git/            # Git repositories
│   └── tenant-name.git/
├── www/            # Nginx-served content (symlinks to sftp/)
│   └── tenant-name/
└── backups/        # Automated backups
    └── daily/

/etc/cdn/
└── config.env      # Main system configuration

/etc/nginx/
├── sites-available/
│   ├── cdn.conf    # CDN server configuration
│   └── gitea.conf  # Gitea reverse proxy
├── sites-enabled/
│   ├── cdn.conf -> ../sites-available/cdn.conf
│   └── gitea.conf -> ../sites-available/gitea.conf
└── dhparam.pem     # DH parameters for SSL

/etc/systemd/system/
├── cdn-autocommit@.service
└── cdn-quota-monitor@.service

/var/log/cdn/
├── cdn-access.log
├── cdn-error.log
├── gitea-access.log
├── gitea-error.log
└── gitea/
    └── gitea.log

/opt/scripts/cdn/
├── templates/      # Configuration templates
├── helpers/        # Helper scripts
├── monitoring/     # Monitoring scripts
└── cdn-*.sh        # Management commands
```

## 🔍 Variable Substitution Syntax

Templates use `${VARIABLE}` syntax for substitution:

```bash
# Simple variable
server_name ${CDN_DOMAIN};

# Variable with default value
port ${SFTP_PORT:-2222};

# Conditional substitution (in script)
if [ "${SMTP_ENABLED}" = "true" ]; then
  # Configure SMTP
fi
```

## ✅ Post-Installation Validation

After template installation, verify:

### 1. Configuration Files

```bash
# Check main configuration
sudo cat /etc/cdn/config.env | grep -v "^#" | grep -v "^$"

# Verify no unsubstituted variables remain
sudo grep -r '\${' /etc/cdn/ /etc/nginx/sites-available/ /etc/systemd/system/cdn-*
```

### 2. File Permissions

```bash
# config.env should be readable by CDN services
sudo ls -la /etc/cdn/config.env

# msmtprc must be 600 (contains passwords)
sudo ls -la /etc/msmtprc

# Systemd services should be 644
sudo ls -la /etc/systemd/system/cdn-*@.service
```

### 3. Nginx Configuration

```bash
# Test configuration syntax
sudo nginx -t

# Verify SSL certificates
sudo ls -la /etc/letsencrypt/live/

# Check cache directory
sudo ls -la /var/cache/nginx/cdn/
```

### 4. Gitea Configuration

```bash
# Verify Gitea config
sudo -u git cat /home/git/gitea/custom/conf/app.ini | grep -E "SECRET_KEY|INTERNAL_TOKEN"

# Check Gitea can start
sudo systemctl status gitea
```

### 5. SMTP Configuration

```bash
# Test email sending
echo "Test email body" | msmtp -a default your-email@example.com

# Check SMTP logs
sudo tail -f /var/log/msmtp.log
```

## 🛠️ Customization Guide

### Adding Custom Variables

1. Add variable to `config.env.template`:
```bash
# Custom configuration
MY_CUSTOM_SETTING=value
```

2. Export in installation script:
```bash
export MY_CUSTOM_SETTING="${MY_CUSTOM_SETTING}"
```

3. Use in other templates:
```bash
some_config ${MY_CUSTOM_SETTING};
```

### Creating Custom Templates

1. Create template file with `.template` extension
2. Use `${VARIABLE}` syntax for substitution
3. Add processing to installation script
4. Document variables in this README

## 📚 Additional Resources

- [Gitea Configuration Cheat Sheet](https://docs.gitea.io/en-us/config-cheat-sheet/)
- [Nginx Configuration Guide](https://nginx.org/en/docs/)
- [msmtp Documentation](https://marlam.de/msmtp/msmtp.html)
- [systemd Service Units](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

## 🐛 Troubleshooting

### Template Variable Not Substituted

**Problem:** Configuration file contains `${VARIABLE}` instead of actual value

**Solution:**
1. Verify variable is defined in `config.env`
2. Ensure variable is exported before template processing
3. Check for typos in variable names
4. Re-run installation script

### SMTP Authentication Failed

**Problem:** Email notifications not working

**Solution:**
1. Verify SMTP credentials: `sudo cat /etc/msmtprc`
2. Test SMTP connection: `msmtp --serverinfo --host=${SMTP_HOST} --port=${SMTP_PORT}`
3. Check SMTP logs: `sudo tail -f /var/log/msmtp.log`
4. For Gmail, ensure App Password is used (not regular password)

### Nginx SSL Certificate Error

**Problem:** SSL certificate not found or invalid

**Solution:**
1. Check certificate exists: `sudo ls -la /etc/letsencrypt/live/${CDN_DOMAIN}/`
2. Verify domain is accessible externally
3. Run certbot manually: `sudo certbot certonly --nginx -d ${CDN_DOMAIN}`
4. Check certificate renewal: `sudo certbot renew --dry-run`

### Systemd Service Won't Start

**Problem:** `cdn-autocommit@tenant` or `cdn-quota-monitor@tenant` fails

**Solution:**
1. Check service status: `systemctl status cdn-autocommit@tenant`
2. View logs: `journalctl -xe -u cdn-autocommit@tenant`
3. Verify directories exist and have correct permissions
4. Test script manually: `sudo ${SCRIPT_DIR}/helpers/cdn-autocommit.sh tenant`
5. Reload systemd: `sudo systemctl daemon-reload`

## 📝 Version History

- **v2.0** - Initial template system with full variable substitution
- Production-ready configurations for all components
- Comprehensive security hardening
- Multi-auth SMTP support
- Real-time quota monitoring

## 🤝 Contributing

When modifying templates:

1. **Always use variables** for configurable values
2. **Document all variables** in this README
3. **Test template processing** before committing
4. **Maintain security hardening** in systemd units
5. **Update examples** if configuration changes

## 📄 License

Part of the Multi-Tenant CDN System v2.0
Copyright (c) 2025 L2C2 Technologies

---

**Need Help?** Check the main project documentation or open an issue on GitHub.
