#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Initial Setup Script (ENHANCED)
# Version: 2.0.1
# Location: /opt/scripts/cdn/cdn-initial-setup.sh
# Purpose: Main entry point for CDN system installation with interactive wizard
#
# ENHANCEMENTS v2.0.1:
# - SMTP test email with confirmation
# - SSH chroot SFTP configuration
# - Explicit msmtp.log creation
# - Gitea admin user creation via CLI
# - Git safe.directory configuration (fixes dubious ownership)
# - Gitea service startup verification
# - Nginx default site removal
# - Explicit nginx cache directory creation
# - Nginx reload after configuration
# - Enhanced logging throughout
################################################################################

set -eEuo pipefail

################################################################################
# CONSTANTS
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="2.0.1"

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
# ERROR HANDLER
################################################################################

error_handler() {
    local exit_code=$?
    local line_no=$1
    
    echo ""
    echo -e "${COLOR_RED}╔════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_RED}║                    INSTALLATION FAILED                     ║${COLOR_NC}"
    echo -e "${COLOR_RED}╚════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    echo -e "${COLOR_RED}Error Code:${COLOR_NC} ${exit_code}"
    echo -e "${COLOR_RED}Location:${COLOR_NC} ${BASH_SOURCE[1]:-unknown}:${line_no}"
    echo -e "${COLOR_RED}Command:${COLOR_NC} ${BASH_COMMAND}"
    echo ""
    
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${COLOR_RED}Stack Trace:${COLOR_NC}"
        local frame=0
        while caller $frame 2>/dev/null; do
            ((frame++))
        done | while read line func file; do
            echo -e "  ${file}:${line} ${func}()"
        done
        echo ""
    fi
    
    error "Installation aborted due to error"
    error "Check logs at: ${LOG_DIR:-/var/log/cdn}/"
    echo ""
    error "To retry: sudo ${SCRIPT_DIR}/${SCRIPT_NAME} --resume"
    echo ""
    
    # Clean up wizard lock file
    rm -f "${WIZARD_LOCK_FILE:-/tmp/cdn-wizard.lock}" 2>/dev/null || true
    
    exit $exit_code
}

trap 'error_handler ${LINENO}' ERR

################################################################################
# PREFLIGHT CHECKS
################################################################################

preflight_checks() {
    info "Running preflight checks..."
    echo ""
    
    # Check required directories
    local -a required_dirs=(
        "${SCRIPT_DIR}/includes"
        "${SCRIPT_DIR}/templates"
    )
    
    # Optional directories (will be created if missing)
    local -a optional_dirs=(
        "${SCRIPT_DIR}/helpers"
        "${SCRIPT_DIR}/lib"
        "${SCRIPT_DIR}/monitoring"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            error "Required directory not found: ${dir}"
            return 1
        fi
        log "✓ Found: ${dir}"
    done
    
    for dir in "${optional_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log "✓ Found: ${dir}"
        else
            warn "Optional directory not found: ${dir} (will be created if needed)"
        fi
    done
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system"
        return 1
    fi
    
    # shellcheck disable=SC1091
    source /etc/os-release
    log "✓ Detected OS: ${ID} ${VERSION_ID}"
    
    if [[ "${ID}" != "ubuntu" ]] && [[ "${ID}" != "debian" ]] && [[ "${ID}" != "centos" ]] && [[ "${ID}" != "rhel" ]] && [[ "${ID}" != "fedora" ]]; then
        warn "OS may not be fully supported: ${ID}"
        warn "This script is tested on Ubuntu, Debian, CentOS, RHEL, and Fedora"
        echo ""
        
        if ! prompt_confirm "Continue anyway?" "no"; then
            error "Installation cancelled due to unsupported OS"
            return 1
        fi
    fi
    
    # Check required commands
    local -a required_cmds=("bash" "sed" "awk" "grep" "cat" "mkdir" "chmod" "chown")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            error "Required command not found: ${cmd}"
            return 1
        fi
    done
    log "✓ All required commands available"
    
    # Check if running in a container (informational)
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        warn "Running inside a container detected"
        warn "Some features may require additional configuration"
        echo ""
    fi
    
    # Check available disk space
    local available_space
    available_space=$(df /srv 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    
    if [[ ${available_space} -lt 1048576 ]]; then
        warn "Low disk space detected: $(df -h /srv 2>/dev/null | tail -1 | awk '{print $4}') available"
        warn "Recommended: at least 1GB free space"
        echo ""
    else
        log "✓ Sufficient disk space available"
    fi
    
    echo ""
    log "✓ All preflight checks passed"
    return 0
}

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
    
    # Run preflight checks
    if ! preflight_checks; then
        error "Preflight checks failed"
        exit 1
    fi
    
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
• Configure SSH chroot SFTP
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
    echo -e "${COLOR_BLUE}║${COLOR_NC}                          Version ${VERSION}                              ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                                                                            ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    log "Starting CDN system setup..."
    echo ""
}

################################################################################
# INTERACTIVE WIZARD - CONTINUED IN NEXT PART
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
    configure_ssh_chroot_sftp  # NEW: SSH chroot configuration
    install_gitea
    configure_nginx
    setup_ssl_certificates
    setup_monitoring
    configure_systemd_services
    finalize_permissions
    
    log "✓ CDN system installation complete!"
}

################################################################################
# INSTALLATION FUNCTIONS START HERE
################################################################################

install_dependencies() {
    info "Installing system dependencies..."
    echo ""
    
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
                rsync \
                || error "Failed to install packages"
            
            log "✓ All packages installed successfully"
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
                rsync \
                || error "Failed to install packages"
            
            log "✓ All packages installed successfully"
            ;;
        
        *)
            error "Unsupported OS: ${os_id}"
            exit 1
            ;;
    esac
    
    log "✓ Dependencies installed"
    echo ""
}

create_directory_structure() {
    info "Creating directory structure..."
    echo ""
    
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
            log "✓ Created: ${dir}"
        else
            log "✓ Exists: ${dir}"
        fi
    done
    
    # Set permissions
    chmod 755 "${BASE_DIR}"
    chmod 755 "${LOG_DIR}"
    chmod 755 "${CACHE_DIR}"
    
    log "✓ Directory structure created"
    echo ""
}

create_system_users() {
    info "Creating system users and groups..."
    echo ""
    
    # Create CDN group (for chroot SFTP)
    if ! getent group "${CDN_GROUP}" &>/dev/null; then
        groupadd "${CDN_GROUP}"
        log "✓ Created group: ${CDN_GROUP}"
    else
        log "✓ Group exists: ${CDN_GROUP}"
    fi
    
    # Create git user for Gitea
    if ! id -u "${GITEA_USER}" &>/dev/null; then
        useradd -r -m -d /home/git -s /bin/bash -c "Gitea User" "${GITEA_USER}"
        log "✓ Created user: ${GITEA_USER}"
    else
        log "✓ User exists: ${GITEA_USER}"
    fi
    
    log "✓ System users and groups created"
    echo ""
}

configure_ssh_chroot_sftp() {
    info "Configuring SSH chroot SFTP..."
    echo ""
    
    local sshd_config="/etc/ssh/sshd_config"
    local sshd_backup="${sshd_config}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Backup SSH config
    if [[ -f "${sshd_config}" ]]; then
        cp "${sshd_config}" "${sshd_backup}"
        log "✓ Backed up SSH config: ${sshd_backup}"
    else
        error "SSH config not found: ${sshd_config}"
        return 1
    fi
    
    # Check if chroot configuration already exists
    if grep -q "Match Group ${CDN_GROUP}" "${sshd_config}"; then
        log "✓ SSH chroot configuration already exists"
    else
        log "Adding chroot SFTP configuration to ${sshd_config}..."
        
        # Append chroot configuration
        cat >> "${sshd_config}" << EOF

################################################################################
# Multi-Tenant CDN - Chroot SFTP Configuration
# Added by cdn-initial-setup.sh on $(date)
################################################################################

Match Group ${CDN_GROUP}
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
    PubkeyAuthentication yes
EOF
        
        log "✓ Added chroot SFTP configuration"
    fi
    
    # Test SSH configuration
    log "Testing SSH configuration..."
    if sshd -t 2>/dev/null; then
        log "✓ SSH configuration is valid"
    else
        error "SSH configuration test failed!"
        error "Output:"
        sshd -t
        error "Restoring backup..."
        mv "${sshd_backup}" "${sshd_config}"
        return 1
    fi
    
    # Restart SSH service
    log "Restarting SSH service..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        log "✓ SSH service restarted successfully"
    else
        error "Failed to restart SSH service"
        error "Restoring backup..."
        mv "${sshd_backup}" "${sshd_config}"
        return 1
    fi
    
    # Verify SSH is still running
    sleep 2
    if systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null; then
        log "✓ SSH service is active and running"
    else
        error "SSH service is not running after restart!"
        error "This is critical - SSH access may be broken"
        error "Manual intervention required"
        return 1
    fi
    
    log "✓ SSH chroot SFTP configured successfully"
    echo ""
}

install_gitea() {
    info "Installing Gitea..."
    echo ""
    
    # Ensure git user exists
    if ! id -u "${GITEA_USER}" &>/dev/null; then
        warn "Git user not found, creating..."
        useradd -r -m -d /home/git -s /bin/bash -c "Gitea User" "${GITEA_USER}"
        log "✓ Created git user"
    else
        log "✓ Git user exists"
    fi
    
    # Download Gitea binary
    local gitea_url="https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64"
    
    if [[ ! -f "/usr/local/bin/gitea" ]]; then
        log "Downloading Gitea ${GITEA_VERSION}..."
        log "URL: ${gitea_url}"
        
        if ! curl -fsSL "${gitea_url}" -o /usr/local/bin/gitea; then
            error "Failed to download Gitea from ${gitea_url}"
            return 1
        fi
        
        # Verify download
        if [[ ! -f "/usr/local/bin/gitea" ]]; then
            error "Gitea binary not found after download"
            return 1
        fi
        
        chmod +x /usr/local/bin/gitea
        log "✓ Gitea binary downloaded and installed"
    else
        log "✓ Gitea binary already installed"
    fi
    
    # Create Gitea directories
    log "Creating Gitea directory structure..."
    mkdir -p /home/git/gitea/{custom,data,log}
    mkdir -p /home/git/gitea/custom/conf
    log "✓ Created Gitea directories"
    
    # Process Gitea configuration template
    local gitea_template="${TEMPLATE_DIR}/gitea-app.ini.template"
    local gitea_config="/home/git/gitea/custom/conf/app.ini"
    
    if [[ -f "${gitea_template}" ]]; then
        log "Processing Gitea configuration template..."
        export GITEA_DOMAIN GITEA_SECRET_KEY GITEA_INTERNAL_TOKEN GITEA_JWT_SECRET
        export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_FROM
        export GIT_DIR
        
        envsubst < "${gitea_template}" > "${gitea_config}"
        chmod 640 "${gitea_config}"
        log "✓ Gitea configuration created"
    else
        warn "Gitea template not found: ${gitea_template}"
    fi
    
    # Set ownership
    chown -R "${GITEA_USER}:${GITEA_USER}" /home/git/
    log "✓ Set ownership on Gitea directories"
    
    # Create Gitea systemd service
    log "Creating Gitea systemd service..."
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
    
    log "✓ Created Gitea systemd service"
    
    # Configure Git safe.directory (CRITICAL FOR FIXING DUBIOUS OWNERSHIP)
    log "Configuring Git safe.directory to prevent 'dubious ownership' errors..."
    sudo -u git git config --global safe.directory '*'
    log "✓ Git safe.directory configured globally for git user"
    
    # Reload systemd and enable Gitea
    systemctl daemon-reload
    systemctl enable gitea
    log "✓ Gitea service enabled"
    
    # Start Gitea service
    log "Starting Gitea service..."
    if systemctl start gitea; then
        log "✓ Gitea service started"
    else
        error "Failed to start Gitea service"
        error "Check logs with: journalctl -xe -u gitea"
        return 1
    fi
    
    # Wait for Gitea to be ready
    log "Waiting for Gitea to initialize (10 seconds)..."
    sleep 10
    
    # Verify Gitea is running
    if systemctl is-active gitea &>/dev/null; then
        log "✓ Gitea service is active and running"
    else
        error "Gitea service failed to start properly"
        error "Service status:"
        systemctl status gitea --no-pager
        error "Recent logs:"
        journalctl -u gitea -n 50 --no-pager
        return 1
    fi
    
    # Create Gitea admin user via CLI
    log "Creating Gitea admin user: ${GITEA_ADMIN_USER}..."
    
    if sudo -u git /usr/local/bin/gitea admin user create \
        --username "${GITEA_ADMIN_USER}" \
        --password "${GITEA_ADMIN_PASS}" \
        --email "${GITEA_ADMIN_EMAIL}" \
        --admin \
        --config /home/git/gitea/custom/conf/app.ini 2>&1 | grep -v "password"; then
        log "✓ Gitea admin user created: ${GITEA_ADMIN_USER}"
    else
        warn "Failed to create Gitea admin user (may already exist)"
        log "You can create it manually later or use existing credentials"
    fi
    
    log "✓ Gitea installed and configured successfully"
    echo ""
}

configure_nginx() {
    info "Configuring Nginx..."
    echo ""
    
    # Remove default nginx site
    log "Removing default Nginx site..."
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
        log "✓ Removed default site symlink"
    fi
    if [[ -f /etc/nginx/sites-available/default ]]; then
        log "  Default site config still exists in sites-available (preserved)"
    fi
    
    # Create nginx cache directory explicitly
    log "Creating Nginx cache directory..."
    if [[ ! -d "${CACHE_DIR}" ]]; then
        mkdir -p "${CACHE_DIR}"
        log "✓ Created: ${CACHE_DIR}"
    else
        log "✓ Cache directory exists: ${CACHE_DIR}"
    fi
    
    # Set ownership on cache directory
    chown -R "${NGINX_USER}:${NGINX_USER}" "${CACHE_DIR}"
    chmod 755 "${CACHE_DIR}"
    log "✓ Set ownership: ${NGINX_USER}:${NGINX_USER} on ${CACHE_DIR}"
    
    # Process nginx templates
    local cdn_template="${TEMPLATE_DIR}/nginx/nginx-cdn.conf.template"
    local gitea_template="${TEMPLATE_DIR}/nginx/nginx-gitea.conf.template"
    
    export CDN_DOMAIN GITEA_DOMAIN NGINX_DIR CACHE_SIZE
    
    if [[ -f "${cdn_template}" ]]; then
        log "Processing CDN nginx template..."
        envsubst < "${cdn_template}" > /etc/nginx/sites-available/cdn.conf
        log "✓ CDN nginx config created"
    else
        error "CDN nginx template not found: ${cdn_template}"
        return 1
    fi
    
    if [[ -f "${gitea_template}" ]]; then
        log "Processing Gitea nginx template..."
        envsubst < "${gitea_template}" > /etc/nginx/sites-available/gitea.conf
        log "✓ Gitea nginx config created"
    else
        error "Gitea nginx template not found: ${gitea_template}"
        return 1
    fi
    
    # Enable sites
    log "Enabling CDN and Gitea sites..."
    ln -sf /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/gitea.conf /etc/nginx/sites-enabled/
    log "✓ Sites enabled"
    
    # Generate DH parameters if not exists
    if [[ ! -f /etc/nginx/dhparam.pem ]]; then
        log "Generating DH parameters (this may take a few minutes)..."
        openssl dhparam -out /etc/nginx/dhparam.pem 2048
        log "✓ DH parameters generated"
    else
        log "✓ DH parameters already exist"
    fi
    
    # Test nginx configuration
    log "Testing Nginx configuration..."
    if nginx -t 2>&1 | tee /tmp/nginx-test.log; then
        log "✓ Nginx configuration is valid"
    else
        error "Nginx configuration test failed!"
        error "Output:"
        cat /tmp/nginx-test.log
        return 1
    fi
    
    # Reload nginx
    log "Reloading Nginx..."
    if systemctl reload nginx; then
        log "✓ Nginx reloaded successfully"
    else
        error "Failed to reload Nginx"
        systemctl status nginx --no-pager
        return 1
    fi
    
    log "✓ Nginx configured successfully"
    echo ""
}

setup_ssl_certificates() {
    info "Setting up SSL certificates..."
    echo ""
    
    if [[ "${SSL_MODE}" == "letsencrypt" ]]; then
        log "Requesting Let's Encrypt certificates..."
        
        # Start nginx to allow ACME challenge
        if ! systemctl is-active nginx &>/dev/null; then
            systemctl start nginx
            log "✓ Started Nginx for ACME challenge"
        fi
        
        # Request certificates
        local certbot_email_flag=""
        if [[ -n "${LE_EMAIL}" ]]; then
            certbot_email_flag="--email ${LE_EMAIL}"
        else
            certbot_email_flag="--register-unsafely-without-email"
        fi
        
        # Request CDN certificate
        log "Requesting certificate for ${CDN_DOMAIN}..."
        if certbot certonly --nginx \
            ${certbot_email_flag} \
            --agree-tos \
            --non-interactive \
            -d "${CDN_DOMAIN}" 2>&1 | tee /tmp/certbot-cdn.log; then
            log "✓ Certificate obtained for ${CDN_DOMAIN}"
        else
            warn "Failed to obtain certificate for ${CDN_DOMAIN}"
            warn "Check logs: /tmp/certbot-cdn.log"
        fi
        
        # Request Gitea certificate
        log "Requesting certificate for ${GITEA_DOMAIN}..."
        if certbot certonly --nginx \
            ${certbot_email_flag} \
            --agree-tos \
            --non-interactive \
            -d "${GITEA_DOMAIN}" 2>&1 | tee /tmp/certbot-gitea.log; then
            log "✓ Certificate obtained for ${GITEA_DOMAIN}"
        else
            warn "Failed to obtain certificate for ${GITEA_DOMAIN}"
            warn "Check logs: /tmp/certbot-gitea.log"
        fi
        
    elif [[ "${SSL_MODE}" == "selfsigned" ]]; then
        log "Generating self-signed certificates..."
        
        # Create self-signed certificates
        mkdir -p /etc/letsencrypt/live/{${CDN_DOMAIN},${GITEA_DOMAIN}}
        
        # CDN certificate
        log "Creating self-signed certificate for ${CDN_DOMAIN}..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/letsencrypt/live/${CDN_DOMAIN}/privkey.pem" \
            -out "/etc/letsencrypt/live/${CDN_DOMAIN}/fullchain.pem" \
            -subj "/CN=${CDN_DOMAIN}"
        log "✓ Self-signed certificate created for ${CDN_DOMAIN}"
        
        # Gitea certificate
        log "Creating self-signed certificate for ${GITEA_DOMAIN}..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/letsencrypt/live/${GITEA_DOMAIN}/privkey.pem" \
            -out "/etc/letsencrypt/live/${GITEA_DOMAIN}/fullchain.pem" \
            -subj "/CN=${GITEA_DOMAIN}"
        log "✓ Self-signed certificate created for ${GITEA_DOMAIN}"
    fi
    
    # Reload nginx with SSL
    log "Reloading Nginx with SSL configuration..."
    if systemctl reload nginx; then
        log "✓ Nginx reloaded with SSL"
    else
        warn "Failed to reload Nginx"
    fi
    
    log "✓ SSL certificates configured"
    echo ""
}

setup_monitoring() {
    info "Setting up monitoring services..."
    echo ""
    
    # Configure msmtp if SMTP enabled
    if [[ "${SMTP_ENABLED}" == "true" ]]; then
        log "Configuring SMTP email relay..."
        
        local msmtp_template="${TEMPLATE_DIR}/msmtprc.template"
        
        if [[ -f "${msmtp_template}" ]]; then
            export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_FROM SMTP_AUTH SMTP_TLS
            
            envsubst < "${msmtp_template}" > /etc/msmtprc
            chmod 600 /etc/msmtprc
            log "✓ Created /etc/msmtprc"
            
            # Create msmtp log file explicitly
            log "Creating msmtp log file..."
            touch /var/log/msmtp.log
            chmod 666 /var/log/msmtp.log
            log "✓ Created /var/log/msmtp.log with permissions 666"
            
            # Send test email
            log "Sending test email to ${ALERT_EMAIL}..."
            echo ""
            
            if echo -e "Subject: CDN System - Installation Complete\n\nThe Multi-Tenant CDN system installation has completed successfully.\n\nDomain: ${CDN_DOMAIN}\nGitea: ${GITEA_DOMAIN}\nTimestamp: $(date)\n\nThis is a test email to confirm SMTP is working." | \
               msmtp -a default "${ALERT_EMAIL}" 2>&1 | tee /tmp/msmtp-test.log; then
                log "✓ Test email sent successfully to ${ALERT_EMAIL}"
                echo ""
                
                # Interactive confirmation
                local email_received=""
                local attempts=0
                while [[ ${attempts} -lt 3 ]]; do
                    echo -ne "${COLOR_CYAN}Did you receive the test email? (yes/no/retry):${COLOR_NC} "
                    read -r email_received
                    email_received="$(echo "${email_received}" | xargs | tr '[:upper:]' '[:lower:]')"
                    
                    case "${email_received}" in
                        yes|y)
                            log "✓ Email delivery confirmed!"
                            break
                            ;;
                        no|n)
                            warn "Test email not received"
                            warn "Please check:"
                            warn "  1. Spam/junk folder"
                            warn "  2. SMTP logs: /var/log/msmtp.log"
                            warn "  3. SMTP configuration: /etc/msmtprc"
                            echo ""
                            
                            if prompt_confirm "Continue despite email issue?" "yes"; then
                                log "Continuing installation..."
                                break
                            else
                                error "Installation cancelled due to email issue"
                                return 1
                            fi
                            ;;
                        retry)
                            log "Resending test email..."
                            echo -e "Subject: CDN System - Test Email (Retry ${attempts})\n\nRetrying email delivery test at $(date)." | \
                               msmtp -a default "${ALERT_EMAIL}" 2>&1
                            log "✓ Test email resent"
                            ((attempts++))
                            ;;
                        *)
                            warn "Please answer 'yes', 'no', or 'retry'"
                            ((attempts++))
                            ;;
                    esac
                done
            else
                error "Failed to send test email"
                warn "Check logs: /var/log/msmtp.log"
                warn "Check configuration: /etc/msmtprc"
                cat /tmp/msmtp-test.log
                echo ""
                
                if prompt_confirm "Continue despite SMTP failure?" "no"; then
                    warn "Continuing without working email notifications"
                else
                    error "Installation cancelled due to SMTP failure"
                    return 1
                fi
            fi
        else
            warn "SMTP template not found: ${msmtp_template}"
        fi
    else
        log "SMTP disabled - skipping email configuration"
    fi
    
    log "✓ Monitoring configured"
    echo ""
}

configure_systemd_services() {
    info "Configuring systemd service templates..."
    echo ""
    
    # Copy service templates
    local autocommit_template="${TEMPLATE_DIR}/systemd/cdn-autocommit@.service.template"
    local quota_template="${TEMPLATE_DIR}/systemd/cdn-quota-monitor@.service.template"
    
    if [[ -f "${autocommit_template}" ]]; then
        cp "${autocommit_template}" /etc/systemd/system/cdn-autocommit@.service
        log "✓ Auto-commit service template installed"
    else
        warn "Auto-commit template not found: ${autocommit_template}"
    fi
    
    if [[ -f "${quota_template}" ]]; then
        cp "${quota_template}" /etc/systemd/system/cdn-quota-monitor@.service
        log "✓ Quota monitor service template installed"
    else
        warn "Quota monitor template not found: ${quota_template}"
    fi
    
    systemctl daemon-reload
    log "✓ Systemd daemon reloaded"
    
    log "✓ Systemd services configured"
    echo ""
}

finalize_permissions() {
    info "Finalizing permissions..."
    echo ""
    
    # Set ownership
    log "Setting directory ownership..."
    chown -R "${NGINX_USER}:${NGINX_USER}" "${NGINX_DIR}"
    log "✓ Nginx directory: ${NGINX_USER}:${NGINX_USER}"
    
    chown -R "${GITEA_USER}:${CDN_GROUP}" "${GIT_DIR}"
    log "✓ Git directory: ${GITEA_USER}:${CDN_GROUP}"
    
    # Set permissions
    chmod 755 "${BASE_DIR}"
    chmod 755 "${SFTP_DIR}"
    chmod 755 "${GIT_DIR}"
    chmod 755 "${NGINX_DIR}"
    log "✓ Directory permissions set to 755"
    
    log "✓ Permissions finalized"
    echo ""
}

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

Gitea Admin Access:
  • URL: https://${GITEA_DOMAIN}/
  • Username: ${GITEA_ADMIN_USER}
  • Email: ${GITEA_ADMIN_EMAIL}
  • Password: [as configured during setup]

Next Steps:
  1. Create your first tenant:
     sudo cdn-tenant-manager add <tenant-name>
  
  2. Upload SSH key for tenant
  
  3. Upload files via SFTP
  
  4. Access content at:
     https://${CDN_DOMAIN}/<tenant-name>/path/to/file
  
  5. View Git history at:
     https://${GITEA_DOMAIN}/<tenant-name>
  
  6. Review documentation:
     /opt/scripts/cdn/README.md"
    
    echo ""
    
    # Show important security reminders
    wizard_info_box "🔒 Security Reminders" \
        "1. Save your Gitea admin credentials securely
2. Regularly update the system: apt-get update && apt-get upgrade
3. Monitor logs: tail -f ${LOG_DIR}/cdn-*.log
4. Backup configuration: ${CONFIG_DIR}/
5. SSL certificates auto-renew via certbot"
    
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
