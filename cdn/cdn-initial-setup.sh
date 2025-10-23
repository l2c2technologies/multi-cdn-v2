#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Initial Setup Script
# Version: 2.0.0
# Location: /opt/scripts/cdn/cdn-initial-setup.sh
# Purpose: Main entry point for CDN system installation with interactive wizard
################################################################################

set -euo pipefail

################################################################################
# CONSTANTS
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="2.0.0"

################################################################################
# SOURCE DEPENDENCIES
################################################################################

# Source common functions library
if [[ ! -f "${SCRIPT_DIR}/includes/common.sh" ]]; then
    echo "ERROR: common.sh not found at ${SCRIPT_DIR}/includes/common.sh"
    exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/includes/common.sh"

# Source wizard common functions
if [[ ! -f "${SCRIPT_DIR}/includes/wizard-common.sh" ]]; then
    error "wizard-common.sh not found at ${SCRIPT_DIR}/includes/wizard-common.sh"
    exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/includes/wizard-common.sh"

################################################################################
# USAGE
################################################################################

usage() {
    cat << EOF
Multi-Tenant CDN System - Initial Setup

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --resume              Resume previous wizard session
  --unattended          Use environment variables (skip wizard)
  --config FILE         Load configuration from file
  --help                Show this help message
  --version             Show version information

Interactive Mode (default):
  Runs 7-step interactive wizard to collect configuration

Unattended Mode:
  export CDN_DOMAIN=cdn.example.com
  export GITEA_DOMAIN=git.example.com
  # ... (see config-from-env.sh for all variables)
  ${SCRIPT_NAME} --unattended

Resume Mode:
  ${SCRIPT_NAME} --resume

Examples:
  ${SCRIPT_NAME}                    # Interactive wizard
  ${SCRIPT_NAME} --resume           # Resume interrupted wizard
  ${SCRIPT_NAME} --unattended       # Use environment variables

Documentation:
  https://github.com/l2c2technologies/multi-cdn-v2

EOF
}

################################################################################
# MAIN SETUP FUNCTION
################################################################################

main() {
    # Parse command line arguments
    local resume_mode=false
    local unattended_mode=false
    local config_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resume)
                resume_mode=true
                shift
                ;;
            --unattended)
                unattended_mode=true
                shift
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --version|-v)
                echo "CDN Initial Setup v${VERSION}"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Ensure running as root
    require_root
    
    # Display banner
    print_banner
    
    # Check if already installed
    if [[ -f "${CONFIG_FILE}" ]] && [[ "${resume_mode}" == "false" ]] && [[ "${unattended_mode}" == "false" ]]; then
        warn "CDN system appears to be already configured"
        echo ""
        echo "Configuration file found: ${CONFIG_FILE}"
        echo ""
        
        if prompt_confirm "Run setup again (will overwrite existing config)?"; then
            info "Re-running setup..."
        else
            info "Setup cancelled"
            exit 0
        fi
    fi
    
    # ========================================================================
    # CONFIGURATION COLLECTION PHASE
    # ========================================================================
    
    if [[ "${unattended_mode}" == "true" ]]; then
        info "Running in UNATTENDED mode (using environment variables)"
        run_unattended_setup
    else
        info "Running in INTERACTIVE mode (wizard)"
        run_interactive_wizard "${resume_mode}"
    fi
    
    # ========================================================================
    # FINALIZE CONFIGURATION
    # ========================================================================
    
    finalize_configuration
    
    # ========================================================================
    # INSTALLATION PHASE
    # ========================================================================
    
    echo ""
    wizard_info_box "Ready to Install" \
        "Configuration complete! 
        
The system will now proceed with installation:
• Install system dependencies
• Create directory structure
• Configure system users and groups
• Install and configure Gitea
• Configure Nginx
• Request SSL certificates
• Setup monitoring services
• Initialize system

This process will take 5-15 minutes."
    
    echo ""
    
    if ! prompt_confirm "Proceed with installation?" "yes"; then
        warn "Installation cancelled by user"
        info "Configuration saved at: ${CONFIG_FILE}"
        info "Run this script again to install"
        exit 0
    fi
    
    run_installation
    
    # ========================================================================
    # POST-INSTALLATION
    # ========================================================================
    
    show_completion_message
}

################################################################################
# PRINT BANNER
################################################################################

print_banner() {
    clear
    echo ""
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                                                                            ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}             ${COLOR_GREEN}Multi-Tenant CDN System - Initial Setup${COLOR_NC}                ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                          Version ${VERSION}                                ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                                                                            ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    log "Starting CDN system setup..."
    echo ""
}

################################################################################
# INTERACTIVE WIZARD
################################################################################

run_interactive_wizard() {
    local resume_mode="$1"
    
    info "Initializing setup wizard..."
    echo ""
    
    # Initialize wizard
    if ! wizard_init; then
        error "Failed to initialize wizard"
        exit 1
    fi
    
    # Check for resume
    if [[ -f "${WIZARD_STATE_FILE}" ]] && [[ "${resume_mode}" == "false" ]]; then
        # shellcheck disable=SC1090
        source "${WIZARD_STATE_FILE}"
        
        if [[ "${WIZARD_COMPLETED:-false}" == "true" ]]; then
            info "Previous wizard session completed on: ${WIZARD_COMPLETED_AT:-unknown}"
            
            if ! prompt_confirm "Start a new wizard session (will overwrite)?"; then
                info "Using existing configuration"
                return 0
            else
                # Reset wizard state
                rm -f "${WIZARD_STATE_FILE}" "${WIZARD_SECRETS_FILE}"
                wizard_init
            fi
        fi
    fi
    
    if [[ "${resume_mode}" == "true" ]]; then
        info "Resuming previous wizard session..."
        
        if [[ ! -f "${WIZARD_STATE_FILE}" ]]; then
            warn "No previous wizard session found"
            resume_mode=false
        else
            # shellcheck disable=SC1090
            source "${WIZARD_STATE_FILE}"
            log "Loaded previous session state"
        fi
    fi
    
    # Run wizard steps
    info "Starting CDN Setup Wizard..."
    echo ""
    
    # Step 1: Domains
    if ! wizard_step_completed "step1-domains" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step1-domains.sh"
        if ! step1_domains; then
            error "Domain configuration failed"
            exit 1
        fi
    else
        log "✓ Step 1 already completed (Domains)"
    fi
    
    # Step 2: SFTP
    if ! wizard_step_completed "step2-sftp" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step2-sftp.sh"
        if ! step2_sftp; then
            error "SFTP configuration failed"
            exit 1
        fi
    else
        log "✓ Step 2 already completed (SFTP)"
    fi
    
    # Step 3: SMTP
    if ! wizard_step_completed "step3-smtp" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step3-smtp.sh"
        if ! step3_smtp; then
            error "SMTP configuration failed"
            exit 1
        fi
    else
        log "✓ Step 3 already completed (SMTP)"
    fi
    
    # Step 4: SSL/TLS
    if ! wizard_step_completed "step4-letsencrypt" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step4-letsencrypt.sh"
        if ! step4_letsencrypt; then
            error "SSL configuration failed"
            exit 1
        fi
    else
        log "✓ Step 4 already completed (SSL/TLS)"
    fi
    
    # Step 5: Paths
    if ! wizard_step_completed "step5-paths" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step5-paths.sh"
        if ! step5_paths; then
            error "Paths configuration failed"
            exit 1
        fi
    else
        log "✓ Step 5 already completed (Paths)"
    fi
    
    # Step 6: Gitea Admin
    if ! wizard_step_completed "step6-gitea-admin" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step6-gitea-admin.sh"
        if ! step6_gitea_admin; then
            error "Gitea configuration failed"
            exit 1
        fi
    else
        log "✓ Step 6 already completed (Gitea Admin)"
    fi
    
    # Step 7: Summary
    if ! wizard_step_completed "step7-summary" || [[ "${resume_mode}" == "true" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/includes/step7-summary.sh"
        if ! step7_summary; then
            error "Configuration review cancelled"
            exit 1
        fi
    else
        log "✓ Step 7 already completed (Summary)"
    fi
    
    log "✓ Interactive wizard completed successfully"
}

################################################################################
# UNATTENDED SETUP
################################################################################

run_unattended_setup() {
    info "Loading configuration from environment variables..."
    
    # Use config-from-env.sh to validate and load environment
    if [[ -f "${SCRIPT_DIR}/config-from-env.sh" ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/config-from-env.sh"
        
        if ! validate_env_config; then
            error "Environment configuration validation failed"
            exit 1
        fi
        
        if ! load_env_config; then
            error "Failed to load environment configuration"
            exit 1
        fi
        
        log "✓ Environment configuration loaded successfully"
    else
        error "config-from-env.sh not found"
        exit 1
    fi
    
    # Initialize wizard state with environment values
    wizard_init
    
    # Save all configuration to wizard state
    save_env_to_state
    
    log "✓ Unattended configuration complete"
}

################################################################################
# FINALIZE CONFIGURATION
################################################################################

finalize_configuration() {
    info "Finalizing configuration files..."
    
    # Create /etc/cdn directory
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
        chmod 700 "${CONFIG_DIR}"
        log "Created: ${CONFIG_DIR}"
    fi
    
    # Move config files to permanent locations
    if [[ -f "${WIZARD_STATE_FILE}.config.env" ]]; then
        mv "${WIZARD_STATE_FILE}.config.env" "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
        log "✓ Installed: ${CONFIG_FILE}"
    else
        # Generate config.env from wizard state
        generate_config_from_state
    fi
    
    if [[ -f "${WIZARD_SECRETS_FILE}" ]]; then
        mv "${WIZARD_SECRETS_FILE}" "${CONFIG_DIR}/secrets.env"
        chmod 600 "${CONFIG_DIR}/secrets.env"
        log "✓ Installed: ${CONFIG_DIR}/secrets.env"
    fi
    
    # Keep wizard state as backup
    if [[ -f "${WIZARD_STATE_FILE}" ]]; then
        cp "${WIZARD_STATE_FILE}" "${CONFIG_DIR}/wizard-state.backup"
        chmod 600 "${CONFIG_DIR}/wizard-state.backup"
        log "✓ Backed up wizard state"
    fi
    
    # Load finalized configuration
    if ! load_configuration; then
        error "Failed to load finalized configuration"
        exit 1
    fi
    
    log "✓ Configuration finalized"
}

################################################################################
# GENERATE CONFIG FROM STATE
################################################################################

generate_config_from_state() {
    info "Generating config.env from wizard state..."
    
    # Load wizard state
    if [[ -f "${WIZARD_STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${WIZARD_STATE_FILE}"
    else
        error "Wizard state file not found"
        return 1
    fi
    
    # Load template
    local template_file="${TEMPLATE_DIR}/config.env.template"
    
    if [[ ! -f "${template_file}" ]]; then
        error "Template not found: ${template_file}"
        return 1
    fi
    
    # Export all variables for envsubst
    export CDN_DOMAIN GITEA_DOMAIN
    export SFTP_PORT SSH_PORT GITEA_PORT=3000
    export BASE_DIR SFTP_DIR GIT_DIR NGINX_DIR BACKUP_DIR
    export CACHE_SIZE BACKUP_RETENTION_DAYS
    export DEFAULT_QUOTA_MB QUOTA_WARN_THRESHOLD_1 QUOTA_WARN_THRESHOLD_2 QUOTA_WARN_THRESHOLD_3
    export GIT_DEFAULT_BRANCH AUTOCOMMIT_DELAY
    export GITEA_VERSION GITEA_ADMIN_USER GITEA_ADMIN_EMAIL
    export SSL_MODE LE_EMAIL
    export SMTP_ENABLED SMTP_HOST SMTP_PORT SMTP_AUTH SMTP_TLS
    export SMTP_USER SMTP_FROM ALERT_EMAIL
    export GITEA_SECRET_KEY GITEA_INTERNAL_TOKEN GITEA_JWT_SECRET
    
    # Set defaults for missing variables
    export GITEA_PORT="${GITEA_PORT:-3000}"
    export LOG_DIR="${LOG_DIR:-/var/log/cdn}"
    export SCRIPT_DIR="${SCRIPT_DIR:-/opt/scripts/cdn}"
    export CACHE_DIR="${CACHE_DIR:-/var/cache/nginx/cdn}"
    export QUOTA_CHECK_INTERVAL="${QUOTA_CHECK_INTERVAL:-30}"
    export QUOTA_ENFORCEMENT="${QUOTA_ENFORCEMENT:-block}"
    export GIT_COMMIT_PREFIX="${GIT_COMMIT_PREFIX:-[AUTO]}"
    export GIT_SYSTEM_USER="${GIT_SYSTEM_USER:-CDN System}"
    export GIT_SYSTEM_EMAIL="${GIT_SYSTEM_EMAIL:-cdn-system@${CDN_DOMAIN}}"
    export BACKUP_COMPRESS="${BACKUP_COMPRESS:-true}"
    export LE_ENVIRONMENT="${LE_ENVIRONMENT:-production}"
    export CDN_GROUP="${CDN_GROUP:-cdnusers}"
    export GITEA_USER="${GITEA_USER:-git}"
    export NGINX_USER="${NGINX_USER:-www-data}"
    export CONFIG_VERSION="${CONFIG_VERSION:-2.0}"
    export CONFIG_LOADED="${CONFIG_LOADED:-true}"
    
    # Process template
    if ! envsubst < "${template_file}" > "${CONFIG_FILE}"; then
        error "Failed to process template"
        return 1
    fi
    
    chmod 600 "${CONFIG_FILE}"
    log "✓ Generated: ${CONFIG_FILE}"
    
    return 0
}

################################################################################
# RUN INSTALLATION
################################################################################

run_installation() {
    info "Starting CDN system installation..."
    echo ""
    
    # Load configuration
    if ! load_configuration; then
        error "Failed to load configuration"
        exit 1
    fi
    
    # Installation steps
    install_dependencies
    create_directory_structure
    create_system_users
    install_gitea
    configure_nginx
    setup_ssl_certificates
    setup_monitoring
    configure_systemd_services
    finalize_permissions
    
    log "✓ CDN system installation complete!"
}

################################################################################
# INSTALLATION STEPS
################################################################################

install_dependencies() {
    info "Installing system dependencies..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        local os_id="${ID}"
        local os_version="${VERSION_ID}"
        
        log "Detected OS: ${os_id} ${os_version}"
    else
        warn "Cannot detect OS, assuming Debian/Ubuntu"
        os_id="ubuntu"
    fi
    
    # Update package list
    log "Updating package list..."
    
    case "${os_id}" in
        ubuntu|debian)
            apt-get update -qq
            
            # Install required packages
            log "Installing packages..."
            apt-get install -y \
                git \
                nginx \
                openssh-server \
                inotify-tools \
                msmtp \
                msmtp-mta \
                certbot \
                python3-certbot-nginx \
                gettext-base \
                sqlite3 \
                curl \
                wget \
                ca-certificates \
                gnupg \
                || error "Failed to install packages"
            ;;
        
        centos|rhel|fedora)
            dnf install -y \
                git \
                nginx \
                openssh-server \
                inotify-tools \
                msmtp \
                certbot \
                python3-certbot-nginx \
                gettext \
                sqlite \
                curl \
                wget \
                ca-certificates \
                || error "Failed to install packages"
            ;;
        
        *)
            error "Unsupported OS: ${os_id}"
            exit 1
            ;;
    esac
    
    log "✓ Dependencies installed"
}

create_directory_structure() {
    info "Creating directory structure..."
    
    # Create base directories
    local -a directories=(
        "${BASE_DIR}"
        "${SFTP_DIR}"
        "${GIT_DIR}"
        "${NGINX_DIR}"
        "${BACKUP_DIR}"
        "${LOG_DIR}"
        "${CACHE_DIR}"
        "/var/www/letsencrypt"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            log "Created: ${dir}"
        else
            log "Exists: ${dir}"
        fi
    done
    
    # Set permissions
    chmod 755 "${BASE_DIR}"
    chmod 755 "${LOG_DIR}"
    chmod 755 "${CACHE_DIR}"
    
    log "✓ Directory structure created"
}

create_system_users() {
    info "Creating system users and groups..."
    
    # Create CDN group
    if ! getent group "${CDN_GROUP}" &>/dev/null; then
        groupadd "${CDN_GROUP}"
        log "Created group: ${CDN_GROUP}"
    else
        log "Group exists: ${CDN_GROUP}"
    fi
    
    # Create git user for Gitea
    if ! id -u "${GITEA_USER}" &>/dev/null; then
        useradd -r -m -d /home/git -s /bin/bash -c "Gitea User" "${GITEA_USER}"
        log "Created user: ${GITEA_USER}"
    else
        log "User exists: ${GITEA_USER}"
    fi
    
    log "✓ System users created"
}

install_gitea() {
    info "Installing Gitea..."
    
    # Download Gitea binary
    local gitea_url="https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64"
    
    if [[ ! -f "/usr/local/bin/gitea" ]]; then
        log "Downloading Gitea ${GITEA_VERSION}..."
        
        if ! curl -fsSL "${gitea_url}" -o /usr/local/bin/gitea; then
            error "Failed to download Gitea"
            return 1
        fi
        
        chmod +x /usr/local/bin/gitea
        log "✓ Gitea binary installed"
    else
        log "Gitea binary already installed"
    fi
    
    # Create Gitea directories
    mkdir -p /home/git/gitea/{custom,data,log}
    mkdir -p /home/git/gitea/custom/conf
    
    # Process Gitea configuration template
    local gitea_template="${TEMPLATE_DIR}/gitea-app.ini.template"
    local gitea_config="/home/git/gitea/custom/conf/app.ini"
    
    if [[ -f "${gitea_template}" ]]; then
        export GITEA_DOMAIN GITEA_SECRET_KEY GITEA_INTERNAL_TOKEN GITEA_JWT_SECRET
        export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_FROM
        export GIT_DIR
        
        envsubst < "${gitea_template}" > "${gitea_config}"
        chmod 600 "${gitea_config}"
        log "✓ Gitea configuration created"
    fi
    
    # Set ownership
    chown -R "${GITEA_USER}:${GITEA_USER}" /home/git/
    
    # Create Gitea systemd service
    cat > /etc/systemd/system/gitea.service << 'EOF'
[Unit]
Description=Gitea (Git with a cup of tea)
After=syslog.target
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/home/git/gitea
ExecStart=/usr/local/bin/gitea web --config /home/git/gitea/custom/conf/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/home/git/gitea

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable gitea
    
    log "✓ Gitea installed and configured"
}

configure_nginx() {
    info "Configuring Nginx..."
    
    # Process nginx templates
    local cdn_template="${TEMPLATE_DIR}/nginx/nginx-cdn.conf.template"
    local gitea_template="${TEMPLATE_DIR}/nginx/nginx-gitea.conf.template"
    
    export CDN_DOMAIN GITEA_DOMAIN NGINX_DIR CACHE_SIZE
    
    if [[ -f "${cdn_template}" ]]; then
        envsubst < "${cdn_template}" > /etc/nginx/sites-available/cdn.conf
        log "✓ CDN nginx config created"
    fi
    
    if [[ -f "${gitea_template}" ]]; then
        envsubst < "${gitea_template}" > /etc/nginx/sites-available/gitea.conf
        log "✓ Gitea nginx config created"
    fi
    
    # Enable sites
    ln -sf /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/gitea.conf /etc/nginx/sites-enabled/
    
    # Generate DH parameters
    if [[ ! -f /etc/nginx/dhparam.pem ]]; then
        log "Generating DH parameters (this may take a few minutes)..."
        openssl dhparam -out /etc/nginx/dhparam.pem 2048
    fi
    
    # Test nginx configuration
    if nginx -t; then
        log "✓ Nginx configuration valid"
    else
        error "Nginx configuration test failed"
        return 1
    fi
    
    log "✓ Nginx configured"
}

setup_ssl_certificates() {
    info "Setting up SSL certificates..."
    
    if [[ "${SSL_MODE}" == "letsencrypt" ]]; then
        log "Requesting Let's Encrypt certificates..."
        
        # Start nginx to allow ACME challenge
        systemctl restart nginx
        
        # Request certificates
        local certbot_email_flag=""
        if [[ -n "${LE_EMAIL}" ]]; then
            certbot_email_flag="--email ${LE_EMAIL}"
        else
            certbot_email_flag="--register-unsafely-without-email"
        fi
        
        # Request CDN certificate
        if ! certbot certonly --nginx \
            ${certbot_email_flag} \
            --agree-tos \
            --non-interactive \
            -d "${CDN_DOMAIN}"; then
            warn "Failed to obtain certificate for ${CDN_DOMAIN}"
        else
            log "✓ Certificate obtained for ${CDN_DOMAIN}"
        fi
        
        # Request Gitea certificate
        if ! certbot certonly --nginx \
            ${certbot_email_flag} \
            --agree-tos \
            --non-interactive \
            -d "${GITEA_DOMAIN}"; then
            warn "Failed to obtain certificate for ${GITEA_DOMAIN}"
        else
            log "✓ Certificate obtained for ${GITEA_DOMAIN}"
        fi
        
    elif [[ "${SSL_MODE}" == "selfsigned" ]]; then
        log "Generating self-signed certificates..."
        
        # Create self-signed certificates
        mkdir -p /etc/letsencrypt/live/{${CDN_DOMAIN},${GITEA_DOMAIN}}
        
        # CDN certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/letsencrypt/live/${CDN_DOMAIN}/privkey.pem" \
            -out "/etc/letsencrypt/live/${CDN_DOMAIN}/fullchain.pem" \
            -subj "/CN=${CDN_DOMAIN}"
        
        # Gitea certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/letsencrypt/live/${GITEA_DOMAIN}/privkey.pem" \
            -out "/etc/letsencrypt/live/${GITEA_DOMAIN}/fullchain.pem" \
            -subj "/CN=${GITEA_DOMAIN}"
        
        log "✓ Self-signed certificates generated"
    fi
    
    # Reload nginx with SSL
    systemctl reload nginx
    
    log "✓ SSL certificates configured"
}

setup_monitoring() {
    info "Setting up monitoring services..."
    
    # Configure msmtp if SMTP enabled
    if [[ "${SMTP_ENABLED}" == "true" ]]; then
        local msmtp_template="${TEMPLATE_DIR}/msmtprc.template"
        
        if [[ -f "${msmtp_template}" ]]; then
            export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_FROM SMTP_AUTH SMTP_TLS
            
            envsubst < "${msmtp_template}" > /etc/msmtprc
            chmod 600 /etc/msmtprc
            
            log "✓ SMTP configured"
        fi
    fi
    
    log "✓ Monitoring configured"
}

configure_systemd_services() {
    info "Configuring systemd service templates..."
    
    # Copy service templates
    local autocommit_template="${TEMPLATE_DIR}/systemd/cdn-autocommit@.service.template"
    local quota_template="${TEMPLATE_DIR}/systemd/cdn-quota-monitor@.service.template"
    
    if [[ -f "${autocommit_template}" ]]; then
        cp "${autocommit_template}" /etc/systemd/system/cdn-autocommit@.service
        log "✓ Auto-commit service template installed"
    fi
    
    if [[ -f "${quota_template}" ]]; then
        cp "${quota_template}" /etc/systemd/system/cdn-quota-monitor@.service
        log "✓ Quota monitor service template installed"
    fi
    
    systemctl daemon-reload
    
    log "✓ Systemd services configured"
}

finalize_permissions() {
    info "Finalizing permissions..."
    
    # Set ownership
    chown -R "${NGINX_USER}:${NGINX_USER}" "${NGINX_DIR}"
    chown -R "${GITEA_USER}:${CDN_GROUP}" "${GIT_DIR}"
    
    # Set permissions
    chmod 755 "${BASE_DIR}"
    chmod 755 "${SFTP_DIR}"
    chmod 755 "${GIT_DIR}"
    chmod 755 "${NGINX_DIR}"
    
    log "✓ Permissions finalized"
}

################################################################################
# COMPLETION MESSAGE
################################################################################

show_completion_message() {
    clear
    
    echo ""
    echo -e "${COLOR_GREEN}╔════════════════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_GREEN}║${COLOR_NC}                                                                            ${COLOR_GREEN}║${COLOR_NC}"
    echo -e "${COLOR_GREEN}║${COLOR_NC}              ${COLOR_GREEN}✓ CDN SYSTEM INSTALLATION COMPLETE!${COLOR_NC}                     ${COLOR_GREEN}║${COLOR_NC}"
    echo -e "${COLOR_GREEN}║${COLOR_NC}                                                                            ${COLOR_GREEN}║${COLOR_NC}"
    echo -e "${COLOR_GREEN}╚════════════════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    
    log "Installation completed successfully!"
    echo ""
    
    wizard_info_box "Installation Summary" \
        "The Multi-Tenant CDN system is now installed and ready to use.

Configuration:
  • Config: ${CONFIG_FILE}
  • Secrets: ${CONFIG_DIR}/secrets.env
  • Logs: ${LOG_DIR}

Access Points:
  • CDN: https://${CDN_DOMAIN}/
  • Gitea: https://${GITEA_DOMAIN}/
  • SFTP: sftp://cdn_<tenant>@${CDN_DOMAIN}:${SFTP_PORT}

Services:
  • Nginx: systemctl status nginx
  • Gitea: systemctl status gitea

Next Steps:
  1. Create your first tenant:
     sudo cdn-tenant-manager add <tenant-name>
  
  2. Access Gitea web interface:
     https://${GITEA_DOMAIN}/
     Username: ${GITEA_ADMIN_USER}
     Password: [as configured]
  
  3. Review documentation:
     /opt/scripts/cdn/README.md"
    
    echo ""
    
    # Clean up wizard temp files
    wizard_cleanup false
    
    log "Thank you for using Multi-Tenant CDN System!"
    echo ""
}

################################################################################
# EXECUTE MAIN
################################################################################

main "$@"
