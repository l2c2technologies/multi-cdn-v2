# Multi-Tenant CDN Setup Wizard

## Overview

The CDN Setup Wizard is an interactive, step-by-step configuration system that guides administrators through the complete setup of the Multi-Tenant CDN system. It collects all necessary configuration parameters, validates inputs, and generates production-ready configuration files.

## Features

- **7-Step Interactive Process**: Logical progression through all configuration aspects
- **Comprehensive Validation**: RFC-compliant domain validation, email validation, port checking, DNS verification
- **SMTP Testing**: Live email testing with multiple provider presets (Gmail, Office365, SendGrid, AWS SES)
- **Firewall Detection**: Automatic detection and guidance for UFW, firewalld, iptables, nftables
- **State Management**: Resume capability with crash recovery
- **Security-First**: Separate secrets file, password strength validation, secure input handling
- **Export Capability**: Export configuration for backup/review
- **Edit Any Step**: Jump back to any step to modify configuration

## Architecture

```
/opt/scripts/cdn/includes/
├── common.sh              # Core utility functions (existing)
├── wizard-common.sh       # Wizard-specific functions (NEW)
├── step1-domains.sh       # Domain configuration
├── step2-sftp.sh          # SFTP/SSH port setup
├── step3-smtp.sh          # Email configuration with presets
├── step4-letsencrypt.sh   # SSL/TLS certificate setup
├── step5-paths.sh         # System paths and caching
├── step6-gitea-admin.sh   # Gitea admin account
└── step7-summary.sh       # Review, edit, confirm
```

## Wizard Steps

### Step 1: Domain Configuration
- Collects CDN domain (e.g., cdn.example.com)
- Collects Gitea domain (e.g., git.example.com)
- Validates RFC-compliant format
- Ensures domains are different
- Shows preview URLs

### Step 2: SFTP Port Configuration
- Detects current SSH port from sshd_config
- Offers to use existing SSH port (recommended)
- Validates port availability
- Checks firewall rules (UFW, firewalld, iptables, nftables)
- Provides configuration guidance for custom ports

### Step 3: SMTP Email Configuration
- Optional: Can be disabled for testing
- **Preset Profiles**:
  - Gmail (with App Password instructions)
  - Microsoft 365
  - SendGrid (API key)
  - AWS SES (with region selection)
  - Custom SMTP server
- Collects: host, port, username, password, from address, alert email
- **Live SMTP Testing**: Sends test email and confirms receipt
- Validates email addresses

### Step 4: SSL/TLS Configuration
- **Let's Encrypt** (production):
  - Optional registrant email
  - DNS verification with dig
  - Port 80/443 availability check
  - Warns about nginx config strategy (no SSL section initially)
- **Self-Signed** (development/testing):
  - Quick setup for non-production
  - Browser warnings expected

### Step 5: Paths and System Configuration
- Base directory with disk space check
- Nginx cache size with validation
- Backup retention period
- Default tenant quota (MB)
- Quota warning thresholds (%, %, %)
- Git configuration (branch name, auto-commit delay)

### Step 6: Gitea Admin Configuration
- Detects current system user
- Username validation (3-40 chars, alphanumeric + dash/underscore/dot)
- Email address (used for notifications)
- Password with strength meter:
  - Minimum 8 characters
  - Complexity scoring (uppercase, lowercase, digits, special chars)
  - Confirmation required
- **Auto-generates security tokens**:
  - SECRET_KEY (64 chars)
  - INTERNAL_TOKEN (105 chars)
  - JWT_SECRET (43 chars)

### Step 7: Configuration Summary
- **Comprehensive review** of all settings
- Actions:
  - ✓ Confirm and proceed
  - 📄 Export configuration to file
  - 📋 View full summary again
  - ✏️ Edit any step (loops back)
  - ❌ Cancel setup
- Generates final config files:
  - `/etc/cdn/config.env` (non-sensitive)
  - `/etc/cdn/secrets.env` (passwords, tokens)

## Installation

### 1. Deploy Wizard Files

```bash
# Run deployment script
sudo ./cdn/deploy.sh

# Verify wizard files
ls -la /opt/scripts/cdn/includes/step*.sh
ls -la /opt/scripts/cdn/includes/wizard-common.sh
```

### 2. Integration with cdn-initial-setup.sh

Add wizard invocation at the beginning of `cdn-initial-setup.sh`:

```bash
#!/bin/bash
################################################################################
# CDN Initial Setup Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/includes/common.sh"
source "${SCRIPT_DIR}/includes/wizard-common.sh"

################################################################################
# Main Setup Function
################################################################################

main() {
    require_root
    
    # Check for resume flag
    local resume_mode=false
    if [[ "${1:-}" == "--resume" ]]; then
        resume_mode=true
        info "Resuming previous wizard session..."
    fi
    
    # Initialize wizard
    if ! wizard_init; then
        error "Failed to initialize wizard"
        exit 1
    fi
    
    # Check if wizard was previously completed
    if [[ -f "${WIZARD_STATE_FILE}" ]]; then
        source "${WIZARD_STATE_FILE}"
        
        if [[ "${WIZARD_COMPLETED:-false}" == "true" ]] && [[ "${resume_mode}" == "false" ]]; then
            info "Configuration already completed on: ${WIZARD_COMPLETED_AT}"
            
            if ! prompt_confirm "Run wizard again (will overwrite)?"; then
                info "Using existing configuration"
                # Load config and proceed to installation
                load_existing_config
                run_installation
                exit 0
            else
                # Reset wizard state
                rm -f "${WIZARD_STATE_FILE}" "${WIZARD_SECRETS_FILE}"
                wizard_init
            fi
        fi
    fi
    
    # Run wizard steps
    info "Starting CDN Setup Wizard..."
    echo ""
    
    # Step 1: Domains
    source "${SCRIPT_DIR}/includes/step1-domains.sh"
    if ! step1_domains; then
        error "Domain configuration failed"
        exit 1
    fi
    
    # Step 2: SFTP
    source "${SCRIPT_DIR}/includes/step2-sftp.sh"
    if ! step2_sftp; then
        error "SFTP configuration failed"
        exit 1
    fi
    
    # Step 3: SMTP
    source "${SCRIPT_DIR}/includes/step3-smtp.sh"
    if ! step3_smtp; then
        error "SMTP configuration failed"
        exit 1
    fi
    
    # Step 4: SSL/TLS
    source "${SCRIPT_DIR}/includes/step4-letsencrypt.sh"
    if ! step4_letsencrypt; then
        error "SSL configuration failed"
        exit 1
    fi
    
    # Step 5: Paths
    source "${SCRIPT_DIR}/includes/step5-paths.sh"
    if ! step5_paths; then
        error "Paths configuration failed"
        exit 1
    fi
    
    # Step 6: Gitea Admin
    source "${SCRIPT_DIR}/includes/step6-gitea-admin.sh"
    if ! step6_gitea_admin; then
        error "Gitea configuration failed"
        exit 1
    fi
    
    # Step 7: Summary
    source "${SCRIPT_DIR}/includes/step7-summary.sh"
    if ! step7_summary; then
        error "Configuration review cancelled"
        exit 1
    fi
    
    # Wizard complete - move temp files to permanent locations
    finalize_configuration
    
    # Proceed with installation
    run_installation
}

################################################################################
# Load Existing Configuration
################################################################################

load_existing_config() {
    info "Loading existing configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Configuration file not found: ${CONFIG_FILE}"
        exit 1
    fi
    
    load_configuration
    
    log "✓ Configuration loaded from ${CONFIG_FILE}"
}

################################################################################
# Finalize Configuration
################################################################################

finalize_configuration() {
    info "Finalizing configuration files..."
    
    # Create /etc/cdn directory
    mkdir -p "${CONFIG_DIR}"
    chmod 700 "${CONFIG_DIR}"
    
    # Move config files to permanent locations
    if [[ -f "${WIZARD_STATE_FILE}.config.env" ]]; then
        mv "${WIZARD_STATE_FILE}.config.env" "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
        log "✓ Installed: ${CONFIG_FILE}"
    fi
    
    if [[ -f "${WIZARD_SECRETS_FILE}" ]]; then
        mv "${WIZARD_SECRETS_FILE}" "${CONFIG_DIR}/secrets.env"
        chmod 600 "${CONFIG_DIR}/secrets.env"
        log "✓ Installed: ${CONFIG_DIR}/secrets.env"
    fi
    
    # Clean up wizard state but keep as backup
    if [[ -f "${WIZARD_STATE_FILE}" ]]; then
        cp "${WIZARD_STATE_FILE}" "${CONFIG_DIR}/wizard-state.backup"
        chmod 600 "${CONFIG_DIR}/wizard-state.backup"
        log "✓ Backed up wizard state"
    fi
    
    # Load finalized configuration
    load_configuration
    
    log "✓ Configuration finalized"
}

################################################################################
# Run Installation
################################################################################

run_installation() {
    info "Starting CDN system installation..."
    echo ""
    
    # [YOUR EXISTING INSTALLATION CODE HERE]
    # This is where the actual system installation happens:
    # - Install dependencies
    # - Create directories
    # - Setup users/groups
    # - Configure services
    # - Install SSL certificates
    # - etc.
    
    log "✓ CDN system installation complete!"
}

################################################################################
# Execute Main
################################################################################

main "$@"
```

## Usage

### First-Time Setup

```bash
# Run setup wizard
sudo cdn-initial-setup

# Wizard will guide through 7 steps
# All inputs are validated in real-time
# Configuration is saved incrementally
```

### Resume After Interruption

```bash
# If wizard was interrupted (Ctrl+C, error, etc.)
sudo cdn-initial-setup --resume

# Wizard state is preserved in /tmp/cdn-wizard-state.env
# Pick up where you left off
```

### Re-run Wizard

```bash
# To start fresh (overwrite existing config)
sudo rm -f /tmp/cdn-wizard-state.env /tmp/cdn-wizard-secrets.env
sudo cdn-initial-setup
```

## State Management

### State Files

```bash
# Temporary wizard state (during setup)
/tmp/cdn-wizard-state.env       # All configuration variables
/tmp/cdn-wizard-secrets.env     # Sensitive data only
/tmp/cdn-wizard.lock           # Process lock file

# Permanent configuration (after wizard completes)
/etc/cdn/config.env            # Non-sensitive configuration
/etc/cdn/secrets.env           # Passwords and tokens (600 permissions)
/etc/cdn/wizard-state.backup   # Wizard state backup
```

### State File Format

```bash
# /tmp/cdn-wizard-state.env
WIZARD_STARTED=2025-01-15T10:30:00Z
WIZARD_CURRENT_STEP=step3-smtp
WIZARD_COMPLETED_STEPS=step1-domains,step2-sftp

CDN_DOMAIN=cdn.example.com
GITEA_DOMAIN=git.example.com
SFTP_PORT=22
# ... all configuration variables
```

## Configuration Variables

### Complete Variable List

See `cdn/templates/config.env.template` for all available variables. The wizard collects or generates:

**User-Provided:**
- Domains (CDN_DOMAIN, GITEA_DOMAIN)
- SFTP port (SFTP_PORT)
- SMTP settings (SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, etc.)
- SSL mode (SSL_MODE, LE_EMAIL)
- Paths (BASE_DIR, CACHE_SIZE, BACKUP_RETENTION_DAYS)
- Quotas (DEFAULT_QUOTA_MB, thresholds)
- Gitea admin (GITEA_ADMIN_USER, GITEA_ADMIN_EMAIL, GITEA_ADMIN_PASS)

**Auto-Generated:**
- Gitea tokens (GITEA_SECRET_KEY, GITEA_INTERNAL_TOKEN, GITEA_JWT_SECRET)

**Defaults Used:**
- All other variables from template (Git config, systemd settings, etc.)

## Validation Rules

### Domains
- RFC 1035/1123 compliant
- Length: 1-253 characters
- Labels: 1-63 characters each
- Characters: a-z, 0-9, hyphen
- DNS resolution check (warning only)
- Must be different (CDN ≠ Gitea)

### Email Addresses
- RFC 5322 format
- Domain part validated separately
- Used for: SMTP user, FROM address, alert recipient, Gitea admin

### Ports
- Range: 1-65535
- Availability check with ss/netstat
- Firewall rule detection
- Privileged port warning (<1024)

### Passwords (Gitea Admin)
- Minimum 8 characters
- Strength scoring:
  - Uppercase letters
  - Lowercase letters
  - Numbers
  - Special characters
  - Length ≥12 chars
- Confirmation required
- Weak passwords allowed with warning

### SMTP
- Live connection test
- Sends actual test email
- User confirms receipt
- Retry mechanism
- Logs at /var/log/msmtp.log

## Security Considerations

### Sensitive Data Handling

1. **Separate Secrets File**: Passwords and tokens in `/etc/cdn/secrets.env` (600 permissions)
2. **No Secrets in Logs**: Passwords never echoed or logged
3. **Secure Input**: Password prompts use `read -s` (no echo)
4. **State File Permissions**: 600 (owner read/write only)
5. **Cleanup on Cancel**: Option to delete state files

### File Permissions

```bash
/etc/cdn/                      # 700 (drwx------)
/etc/cdn/config.env            # 600 (-rw-------)
/etc/cdn/secrets.env           # 600 (-rw-------)
/etc/cdn/wizard-state.backup   # 600 (-rw-------)
/tmp/cdn-wizard-state.env      # 600 (-rw-------)
/tmp/cdn-wizard-secrets.env    # 600 (-rw-------)
```

### Exported Configuration

When exporting configuration:
- Passwords marked as [HIDDEN]
- Token lengths shown instead of values
- File created with 600 permissions
- User warned about sensitive data
- Recommend deletion after use

## Error Handling

### Permissive Mode

The wizard uses "permissive mode" - it **warns but allows proceeding**:

- DNS doesn't resolve → warn, allow continue
- Port in use → warn, allow continue
- Firewall may block → warn, allow continue
- SMTP test fails → warn, allow continue

This approach supports:
- Testing/staging environments
- Pre-production setups
- Environments with incomplete DNS
- Planned manual configuration

### Resume Capability

If wizard is interrupted:

```bash
# State preserved in /tmp/
sudo cdn-initial-setup --resume

# Wizard detects completed steps
# Skips to last incomplete step
```

### Validation Failures

Hard failures (exit) only for:
- Invalid input format (after 5 attempts)
- User cancellation
- Missing required tools
- Permission errors

## SMTP Preset Profiles

### Gmail

```
Host: smtp.gmail.com
Port: 587
Auth: plain
TLS: starttls

Requirements:
1. Enable 2FA
2. Generate App Password
3. Use App Password (not account password)
```

### Microsoft 365

```
Host: smtp.office365.com
Port: 587
Auth: login
TLS: starttls

Requirements:
1. Use full email as username
2. Regular password
3. SMTP AUTH enabled in admin panel
```

### SendGrid

```
Host: smtp.sendgrid.net
Port: 587
Auth: plain
TLS: starttls

Requirements:
1. Create API key
2. Username: "apikey" (literal)
3. Password: Your API key
4. Verify sender email
```

### AWS SES

```
Host: email-smtp.<region>.amazonaws.com
Port: 587
Auth: plain
TLS: starttls

Requirements:
1. Create SMTP credentials in SES
2. Verify email/domain
3. Request production access
4. Select your AWS region
```

## Troubleshooting

### Wizard Won't Start

```bash
# Check for lock file
ls -la /tmp/cdn-wizard.lock

# If stale, remove
sudo rm -f /tmp/cdn-wizard.lock

# Check for existing state
cat /tmp/cdn-wizard-state.env
```

### DNS Verification Fails

```bash
# Manual DNS check
dig +short cdn.example.com
host git.example.com
nslookup cdn.example.com

# If not resolving:
# 1. Check DNS provider settings
# 2. Wait for propagation (up to 48h)
# 3. Use --resume after DNS is ready
```

### SMTP Test Fails

```bash
# Check SMTP logs
sudo tail -f /var/log/msmtp.log

# Test manually
echo "test" | msmtp -a default test@example.com

# Check msmtprc
sudo cat /etc/msmtprc

# Common issues:
# - Wrong App Password (Gmail)
# - 2FA not enabled (Gmail)
# - Firewall blocking port 587
# - Wrong authentication method
```

### Port Already in Use

```bash
# Check what's using the port
sudo ss -tulnp | grep :22
sudo lsof -i :22

# Options:
# 1. Stop conflicting service
# 2. Use different port
# 3. Continue anyway (wizard allows)
```

### Firewall Blocking

```bash
# UFW
sudo ufw status
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# firewalld
sudo firewall-cmd --list-ports
sudo firewall-cmd --add-port=22/tcp --permanent
sudo firewall-cmd --reload

# iptables
sudo iptables -L -n
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

## Development

### Testing Individual Steps

Each step file can be run standalone for testing:

```bash
# Test step 1
sudo bash /opt/scripts/cdn/includes/step1-domains.sh

# Test step 3 with mocked state
export CDN_DOMAIN="cdn.test.com"
export GITEA_DOMAIN="git.test.com"
sudo bash /opt/scripts/cdn/includes/step3-smtp.sh
```

### Adding New Validation

Edit `includes/wizard-common.sh`:

```bash
# Add custom validation function
validate_custom_field() {
    local value="$1"
    
    # Your validation logic
    if [[ ! "${value}" =~ ^pattern$ ]]; then
        error "Invalid format"
        return 1
    fi
    
    return 0
}

# Use in prompt
result=$(prompt_input "Enter value" "" "validate_custom_field")
```

### Extending Steps

To add a new step:

1. Create `/opt/scripts/cdn/includes/step8-newfeature.sh`
2. Follow existing step structure
3. Call `wizard_save_state` for each variable
4. Call `wizard_complete_step "step8-newfeature"`
5. Update `cdn-initial-setup.sh` to source and call step
6. Update `WIZARD_STEPS` array in `wizard-common.sh`

## License

Part of Multi-Tenant CDN System v2.0
Copyright (c) 2025 L2C2 Technologies

## Support

- GitHub: https://github.com/l2c2technologies/multi-cdn-v2
- Issues: https://github.com/l2c2technologies/multi-cdn-v2/issues
- Documentation: See `/opt/scripts/cdn/README.md`
