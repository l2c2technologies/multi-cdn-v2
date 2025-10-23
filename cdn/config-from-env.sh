#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Configuration from Environment Variables
# Version: 2.0.0
# Location: /opt/scripts/cdn/config-from-env.sh
# Purpose: Load and validate configuration from environment variables
#          for unattended/CI-CD installations
################################################################################

# This file is sourced by cdn-initial-setup.sh when using --unattended flag

################################################################################
# ENVIRONMENT VARIABLE REQUIREMENTS
################################################################################

# This script expects the following environment variables to be set:

# REQUIRED VARIABLES:
# - CDN_DOMAIN           : CDN content delivery domain
# - GITEA_DOMAIN         : Gitea web interface domain
# - GITEA_ADMIN_USER     : Gitea admin username
# - GITEA_ADMIN_EMAIL    : Gitea admin email
# - GITEA_ADMIN_PASS     : Gitea admin password

# OPTIONAL VARIABLES (with defaults):
# - SFTP_PORT            : SFTP port (default: 22)
# - BASE_DIR             : Base data directory (default: /srv/cdn)
# - CACHE_SIZE           : Nginx cache size (default: 10g)
# - DEFAULT_QUOTA_MB     : Default tenant quota MB (default: 5120)
# - SSL_MODE             : letsencrypt or selfsigned (default: letsencrypt)
# - LE_EMAIL             : Let's Encrypt email (optional)
# - SMTP_ENABLED         : Enable SMTP (default: false)
# - SMTP_HOST            : SMTP server hostname
# - SMTP_PORT            : SMTP server port (default: 587)
# - SMTP_USER            : SMTP username
# - SMTP_PASS            : SMTP password
# - SMTP_FROM            : SMTP from address
# - ALERT_EMAIL          : Alert recipient email
# - BACKUP_RETENTION_DAYS: Backup retention days (default: 30)
# - GIT_DEFAULT_BRANCH   : Default git branch (default: main)
# - AUTOCOMMIT_DELAY     : Auto-commit delay seconds (default: 60)

################################################################################
# VALIDATE ENVIRONMENT CONFIGURATION
################################################################################

validate_env_config() {
    local validation_passed=true
    
    info "Validating environment configuration..."
    echo ""
    
    # ========================================================================
    # REQUIRED VARIABLES
    # ========================================================================
    
    # CDN_DOMAIN
    if [[ -z "${CDN_DOMAIN:-}" ]]; then
        error "CDN_DOMAIN is required"
        validation_passed=false
    else
        if ! validate_domain "${CDN_DOMAIN}"; then
            error "CDN_DOMAIN is invalid: ${CDN_DOMAIN}"
            validation_passed=false
        else
            log "✓ CDN_DOMAIN: ${CDN_DOMAIN}"
        fi
    fi
    
    # GITEA_DOMAIN
    if [[ -z "${GITEA_DOMAIN:-}" ]]; then
        error "GITEA_DOMAIN is required"
        validation_passed=false
    else
        if ! validate_domain "${GITEA_DOMAIN}"; then
            error "GITEA_DOMAIN is invalid: ${GITEA_DOMAIN}"
            validation_passed=false
        else
            log "✓ GITEA_DOMAIN: ${GITEA_DOMAIN}"
        fi
    fi
    
    # Ensure domains are different
    if [[ "${CDN_DOMAIN:-}" == "${GITEA_DOMAIN:-}" ]]; then
        error "CDN_DOMAIN and GITEA_DOMAIN must be different"
        validation_passed=false
    fi
    
    # GITEA_ADMIN_USER
    if [[ -z "${GITEA_ADMIN_USER:-}" ]]; then
        error "GITEA_ADMIN_USER is required"
        validation_passed=false
    else
        if [[ ! "${GITEA_ADMIN_USER}" =~ ^[a-zA-Z0-9._-]{3,40}$ ]]; then
            error "GITEA_ADMIN_USER invalid format: ${GITEA_ADMIN_USER}"
            error "Must be 3-40 characters: letters, numbers, dash, underscore, dot"
            validation_passed=false
        else
            log "✓ GITEA_ADMIN_USER: ${GITEA_ADMIN_USER}"
        fi
    fi
    
    # GITEA_ADMIN_EMAIL
    if [[ -z "${GITEA_ADMIN_EMAIL:-}" ]]; then
        error "GITEA_ADMIN_EMAIL is required"
        validation_passed=false
    else
        if ! validate_email "${GITEA_ADMIN_EMAIL}"; then
            error "GITEA_ADMIN_EMAIL is invalid: ${GITEA_ADMIN_EMAIL}"
            validation_passed=false
        else
            log "✓ GITEA_ADMIN_EMAIL: ${GITEA_ADMIN_EMAIL}"
        fi
    fi
    
    # GITEA_ADMIN_PASS
    if [[ -z "${GITEA_ADMIN_PASS:-}" ]]; then
        error "GITEA_ADMIN_PASS is required"
        validation_passed=false
    else
        if [[ ${#GITEA_ADMIN_PASS} -lt 8 ]]; then
            error "GITEA_ADMIN_PASS must be at least 8 characters"
            validation_passed=false
        else
            log "✓ GITEA_ADMIN_PASS: [HIDDEN - ${#GITEA_ADMIN_PASS} characters]"
        fi
    fi
    
    # ========================================================================
    # OPTIONAL VARIABLES WITH VALIDATION
    # ========================================================================
    
    # SFTP_PORT
    if [[ -n "${SFTP_PORT:-}" ]]; then
        if ! validate_port "${SFTP_PORT}"; then
            error "SFTP_PORT is invalid: ${SFTP_PORT}"
            validation_passed=false
        else
            log "✓ SFTP_PORT: ${SFTP_PORT}"
        fi
    fi
    
    # BASE_DIR
    if [[ -n "${BASE_DIR:-}" ]]; then
        if [[ ! "${BASE_DIR}" =~ ^/ ]]; then
            error "BASE_DIR must be an absolute path: ${BASE_DIR}"
            validation_passed=false
        else
            log "✓ BASE_DIR: ${BASE_DIR}"
        fi
    fi
    
    # CACHE_SIZE
    if [[ -n "${CACHE_SIZE:-}" ]]; then
        if [[ ! "${CACHE_SIZE}" =~ ^[0-9]+[kmgtKMGT]$ ]]; then
            error "CACHE_SIZE invalid format: ${CACHE_SIZE}"
            error "Use format: 10g, 500m, 50g, etc."
            validation_passed=false
        else
            log "✓ CACHE_SIZE: ${CACHE_SIZE}"
        fi
    fi
    
    # DEFAULT_QUOTA_MB
    if [[ -n "${DEFAULT_QUOTA_MB:-}" ]]; then
        if ! [[ "${DEFAULT_QUOTA_MB}" =~ ^[0-9]+$ ]] || [[ ${DEFAULT_QUOTA_MB} -lt 1 ]]; then
            error "DEFAULT_QUOTA_MB must be a positive integer: ${DEFAULT_QUOTA_MB}"
            validation_passed=false
        else
            log "✓ DEFAULT_QUOTA_MB: ${DEFAULT_QUOTA_MB}"
        fi
    fi
    
    # SSL_MODE
    if [[ -n "${SSL_MODE:-}" ]]; then
        if [[ "${SSL_MODE}" != "letsencrypt" ]] && [[ "${SSL_MODE}" != "selfsigned" ]]; then
            error "SSL_MODE must be 'letsencrypt' or 'selfsigned': ${SSL_MODE}"
            validation_passed=false
        else
            log "✓ SSL_MODE: ${SSL_MODE}"
        fi
    fi
    
    # LE_EMAIL
    if [[ -n "${LE_EMAIL:-}" ]]; then
        if ! validate_email "${LE_EMAIL}"; then
            error "LE_EMAIL is invalid: ${LE_EMAIL}"
            validation_passed=false
        else
            log "✓ LE_EMAIL: ${LE_EMAIL}"
        fi
    fi
    
    # ========================================================================
    # SMTP VALIDATION (if enabled)
    # ========================================================================
    
    if [[ "${SMTP_ENABLED:-false}" == "true" ]]; then
        log "SMTP enabled, validating SMTP configuration..."
        
        # SMTP_HOST
        if [[ -z "${SMTP_HOST:-}" ]]; then
            error "SMTP_HOST is required when SMTP_ENABLED=true"
            validation_passed=false
        else
            if ! validate_domain "${SMTP_HOST}"; then
                error "SMTP_HOST is invalid: ${SMTP_HOST}"
                validation_passed=false
            else
                log "✓ SMTP_HOST: ${SMTP_HOST}"
            fi
        fi
        
        # SMTP_PORT
        if [[ -z "${SMTP_PORT:-}" ]]; then
            warn "SMTP_PORT not set, using default: 587"
            export SMTP_PORT=587
        else
            if ! validate_port "${SMTP_PORT}"; then
                error "SMTP_PORT is invalid: ${SMTP_PORT}"
                validation_passed=false
            else
                log "✓ SMTP_PORT: ${SMTP_PORT}"
            fi
        fi
        
        # SMTP_USER
        if [[ -z "${SMTP_USER:-}" ]]; then
            error "SMTP_USER is required when SMTP_ENABLED=true"
            validation_passed=false
        else
            if ! validate_email "${SMTP_USER}"; then
                error "SMTP_USER is invalid: ${SMTP_USER}"
                validation_passed=false
            else
                log "✓ SMTP_USER: ${SMTP_USER}"
            fi
        fi
        
        # SMTP_PASS
        if [[ -z "${SMTP_PASS:-}" ]]; then
            error "SMTP_PASS is required when SMTP_ENABLED=true"
            validation_passed=false
        else
            log "✓ SMTP_PASS: [HIDDEN]"
        fi
        
        # SMTP_FROM
        if [[ -z "${SMTP_FROM:-}" ]]; then
            warn "SMTP_FROM not set, using: cdn-system@${CDN_DOMAIN}"
            export SMTP_FROM="cdn-system@${CDN_DOMAIN}"
        else
            if ! validate_email "${SMTP_FROM}"; then
                error "SMTP_FROM is invalid: ${SMTP_FROM}"
                validation_passed=false
            else
                log "✓ SMTP_FROM: ${SMTP_FROM}"
            fi
        fi
        
        # ALERT_EMAIL
        if [[ -z "${ALERT_EMAIL:-}" ]]; then
            error "ALERT_EMAIL is required when SMTP_ENABLED=true"
            validation_passed=false
        else
            if ! validate_email "${ALERT_EMAIL}"; then
                error "ALERT_EMAIL is invalid: ${ALERT_EMAIL}"
                validation_passed=false
            else
                log "✓ ALERT_EMAIL: ${ALERT_EMAIL}"
            fi
        fi
        
        # SMTP_AUTH (default)
        if [[ -z "${SMTP_AUTH:-}" ]]; then
            export SMTP_AUTH="plain"
            log "✓ SMTP_AUTH: plain (default)"
        else
            log "✓ SMTP_AUTH: ${SMTP_AUTH}"
        fi
        
        # SMTP_TLS (default)
        if [[ -z "${SMTP_TLS:-}" ]]; then
            export SMTP_TLS="starttls"
            log "✓ SMTP_TLS: starttls (default)"
        else
            log "✓ SMTP_TLS: ${SMTP_TLS}"
        fi
    else
        log "✓ SMTP_ENABLED: false (disabled)"
    fi
    
    # ========================================================================
    # QUOTA THRESHOLDS
    # ========================================================================
    
    if [[ -n "${QUOTA_WARN_THRESHOLD_1:-}" ]]; then
        if ! [[ "${QUOTA_WARN_THRESHOLD_1}" =~ ^[0-9]+$ ]] || [[ ${QUOTA_WARN_THRESHOLD_1} -lt 1 ]] || [[ ${QUOTA_WARN_THRESHOLD_1} -gt 100 ]]; then
            error "QUOTA_WARN_THRESHOLD_1 must be 1-100: ${QUOTA_WARN_THRESHOLD_1}"
            validation_passed=false
        fi
    fi
    
    if [[ -n "${QUOTA_WARN_THRESHOLD_2:-}" ]]; then
        if ! [[ "${QUOTA_WARN_THRESHOLD_2}" =~ ^[0-9]+$ ]] || [[ ${QUOTA_WARN_THRESHOLD_2} -lt 1 ]] || [[ ${QUOTA_WARN_THRESHOLD_2} -gt 100 ]]; then
            error "QUOTA_WARN_THRESHOLD_2 must be 1-100: ${QUOTA_WARN_THRESHOLD_2}"
            validation_passed=false
        fi
    fi
    
    if [[ -n "${QUOTA_WARN_THRESHOLD_3:-}" ]]; then
        if ! [[ "${QUOTA_WARN_THRESHOLD_3}" =~ ^[0-9]+$ ]] || [[ ${QUOTA_WARN_THRESHOLD_3} -lt 1 ]] || [[ ${QUOTA_WARN_THRESHOLD_3} -gt 100 ]]; then
            error "QUOTA_WARN_THRESHOLD_3 must be 1-100: ${QUOTA_WARN_THRESHOLD_3}"
            validation_passed=false
        fi
    fi
    
    # ========================================================================
    # BACKUP RETENTION
    # ========================================================================
    
    if [[ -n "${BACKUP_RETENTION_DAYS:-}" ]]; then
        if ! [[ "${BACKUP_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [[ ${BACKUP_RETENTION_DAYS} -lt 1 ]]; then
            error "BACKUP_RETENTION_DAYS must be a positive integer: ${BACKUP_RETENTION_DAYS}"
            validation_passed=false
        else
            log "✓ BACKUP_RETENTION_DAYS: ${BACKUP_RETENTION_DAYS}"
        fi
    fi
    
    # ========================================================================
    # GIT CONFIGURATION
    # ========================================================================
    
    if [[ -n "${AUTOCOMMIT_DELAY:-}" ]]; then
        if ! [[ "${AUTOCOMMIT_DELAY}" =~ ^[0-9]+$ ]] || [[ ${AUTOCOMMIT_DELAY} -lt 1 ]]; then
            error "AUTOCOMMIT_DELAY must be a positive integer: ${AUTOCOMMIT_DELAY}"
            validation_passed=false
        else
            log "✓ AUTOCOMMIT_DELAY: ${AUTOCOMMIT_DELAY}"
        fi
    fi
    
    if [[ -n "${GIT_DEFAULT_BRANCH:-}" ]]; then
        log "✓ GIT_DEFAULT_BRANCH: ${GIT_DEFAULT_BRANCH}"
    fi
    
    # ========================================================================
    # VALIDATION RESULT
    # ========================================================================
    
    echo ""
    
    if [[ "${validation_passed}" == "true" ]]; then
        log "✓ Environment configuration validation PASSED"
        return 0
    else
        error "Environment configuration validation FAILED"
        error "Please fix the errors above and try again"
        return 1
    fi
}

################################################################################
# LOAD ENVIRONMENT CONFIGURATION
################################################################################

load_env_config() {
    info "Loading configuration from environment variables..."
    echo ""
    
    # ========================================================================
    # SET DEFAULTS FOR OPTIONAL VARIABLES
    # ========================================================================
    
    # Network
    export SFTP_PORT="${SFTP_PORT:-22}"
    export SSH_PORT="${SSH_PORT:-22}"
    export GITEA_PORT="${GITEA_PORT:-3000}"
    
    # Directories
    export BASE_DIR="${BASE_DIR:-/srv/cdn}"
    export SFTP_DIR="${SFTP_DIR:-${BASE_DIR}/sftp}"
    export GIT_DIR="${GIT_DIR:-${BASE_DIR}/git}"
    export NGINX_DIR="${NGINX_DIR:-${BASE_DIR}/www}"
    export BACKUP_DIR="${BACKUP_DIR:-${BASE_DIR}/backups}"
    export LOG_DIR="${LOG_DIR:-/var/log/cdn}"
    export SCRIPT_DIR="${SCRIPT_DIR:-/opt/scripts/cdn}"
    export CACHE_DIR="${CACHE_DIR:-/var/cache/nginx/cdn}"
    
    # Cache
    export CACHE_SIZE="${CACHE_SIZE:-10g}"
    export CACHE_INACTIVE="${CACHE_INACTIVE:-30d}"
    
    # Quota
    export DEFAULT_QUOTA_MB="${DEFAULT_QUOTA_MB:-5120}"
    export QUOTA_WARN_THRESHOLD_1="${QUOTA_WARN_THRESHOLD_1:-70}"
    export QUOTA_WARN_THRESHOLD_2="${QUOTA_WARN_THRESHOLD_2:-80}"
    export QUOTA_WARN_THRESHOLD_3="${QUOTA_WARN_THRESHOLD_3:-90}"
    export QUOTA_CHECK_INTERVAL="${QUOTA_CHECK_INTERVAL:-30}"
    export QUOTA_ENFORCEMENT="${QUOTA_ENFORCEMENT:-block}"
    
    # Git
    export GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
    export AUTOCOMMIT_DELAY="${AUTOCOMMIT_DELAY:-60}"
    export GIT_COMMIT_PREFIX="${GIT_COMMIT_PREFIX:-[AUTO]}"
    export GIT_SYSTEM_USER="${GIT_SYSTEM_USER:-CDN System}"
    export GIT_SYSTEM_EMAIL="${GIT_SYSTEM_EMAIL:-cdn-system@${CDN_DOMAIN}}"
    
    # Backup
    export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
    export BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
    export BACKUP_COMPRESS="${BACKUP_COMPRESS:-true}"
    export BACKUP_INCLUDE_GIT="${BACKUP_INCLUDE_GIT:-true}"
    export BACKUP_INCLUDE_DB="${BACKUP_INCLUDE_DB:-true}"
    
    # SSL/TLS
    export SSL_MODE="${SSL_MODE:-letsencrypt}"
    export LE_EMAIL="${LE_EMAIL:-}"
    export LE_ENVIRONMENT="${LE_ENVIRONMENT:-production}"
    export DNS_VERIFIED="${DNS_VERIFIED:-false}"
    
    # SMTP
    export SMTP_ENABLED="${SMTP_ENABLED:-false}"
    export SMTP_PROFILE="${SMTP_PROFILE:-custom}"
    export SMTP_HOST="${SMTP_HOST:-}"
    export SMTP_PORT="${SMTP_PORT:-587}"
    export SMTP_AUTH="${SMTP_AUTH:-plain}"
    export SMTP_TLS="${SMTP_TLS:-starttls}"
    export SMTP_USER="${SMTP_USER:-}"
    export SMTP_PASS="${SMTP_PASS:-}"
    export SMTP_FROM="${SMTP_FROM:-cdn-system@${CDN_DOMAIN}}"
    export ALERT_EMAIL="${ALERT_EMAIL:-admin@${CDN_DOMAIN}}"
    
    # Gitea
    export GITEA_VERSION="${GITEA_VERSION:-1.24.6}"
    export GITEA_BINARY="${GITEA_BINARY:-/usr/local/bin/gitea}"
    export GITEA_WORK_DIR="${GITEA_WORK_DIR:-/home/git/gitea}"
    export GITEA_CONFIG="${GITEA_CONFIG:-/home/git/gitea/custom/conf/app.ini}"
    
    # Generate Gitea secrets if not provided
    if [[ -z "${GITEA_SECRET_KEY:-}" ]]; then
        info "Generating GITEA_SECRET_KEY..."
        if ! generate_gitea_secrets; then
            error "Failed to generate Gitea secrets"
            return 1
        fi
    else
        export GITEA_SECRET_KEY="${GITEA_SECRET_KEY}"
        export GITEA_INTERNAL_TOKEN="${GITEA_INTERNAL_TOKEN}"
        export GITEA_JWT_SECRET="${GITEA_JWT_SECRET}"
    fi
    
    # System users
    export CDN_GROUP="${CDN_GROUP:-cdnusers}"
    export GITEA_USER="${GITEA_USER:-git}"
    export NGINX_USER="${NGINX_USER:-www-data}"
    
    # Performance
    export NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-auto}"
    export NGINX_WORKER_CONNECTIONS="${NGINX_WORKER_CONNECTIONS:-1024}"
    export GITEA_DB_TYPE="${GITEA_DB_TYPE:-sqlite3}"
    export GITEA_DB_MAX_CONNECTIONS="${GITEA_DB_MAX_CONNECTIONS:-100}"
    
    # Feature flags
    export ENABLE_GIT_LFS="${ENABLE_GIT_LFS:-false}"
    export ENABLE_API="${ENABLE_API:-false}"
    export ENABLE_WEB_FILEMANAGER="${ENABLE_WEB_FILEMANAGER:-false}"
    export ENABLE_ANALYTICS="${ENABLE_ANALYTICS:-false}"
    
    # Monitoring
    export LOG_ROTATE_SIZE="${LOG_ROTATE_SIZE:-100}"
    export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"
    export VERBOSE_LOGGING="${VERBOSE_LOGGING:-false}"
    export SYSTEMD_LOGGING="${SYSTEMD_LOGGING:-true}"
    
    # Security
    export SSH_KEY_TYPES="${SSH_KEY_TYPES:-ed25519,rsa}"
    export SSH_MIN_RSA_BITS="${SSH_MIN_RSA_BITS:-2048}"
    export MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-104857600}"
    export ENABLE_FILE_TYPE_RESTRICTIONS="${ENABLE_FILE_TYPE_RESTRICTIONS:-false}"
    export ALLOWED_FILE_EXTENSIONS="${ALLOWED_FILE_EXTENSIONS:-html,css,js,jpg,jpeg,png,gif,svg,webp,pdf,zip}"
    
    # Config metadata
    export CONFIG_VERSION="${CONFIG_VERSION:-2.0}"
    export CONFIG_LOADED="${CONFIG_LOADED:-true}"
    
    log "✓ Configuration loaded from environment"
    
    # Display summary
    echo ""
    log "Configuration Summary:"
    log "  CDN Domain: ${CDN_DOMAIN}"
    log "  Gitea Domain: ${GITEA_DOMAIN}"
    log "  SFTP Port: ${SFTP_PORT}"
    log "  Base Directory: ${BASE_DIR}"
    log "  SSL Mode: ${SSL_MODE}"
    log "  SMTP Enabled: ${SMTP_ENABLED}"
    log "  Gitea Admin: ${GITEA_ADMIN_USER}"
    echo ""
    
    return 0
}

################################################################################
# SAVE ENVIRONMENT TO WIZARD STATE
################################################################################

save_env_to_state() {
    info "Saving environment configuration to wizard state..."
    
    # This function saves all loaded environment variables to wizard state file
    # so they can be used by the installation process
    
    # Domains
    wizard_save_state "CDN_DOMAIN" "${CDN_DOMAIN}"
    wizard_save_state "GITEA_DOMAIN" "${GITEA_DOMAIN}"
    
    # Network
    wizard_save_state "SFTP_PORT" "${SFTP_PORT}"
    wizard_save_state "SSH_PORT" "${SSH_PORT}"
    wizard_save_state "GITEA_PORT" "${GITEA_PORT}"
    
    # Directories
    wizard_save_state "BASE_DIR" "${BASE_DIR}"
    wizard_save_state "SFTP_DIR" "${SFTP_DIR}"
    wizard_save_state "GIT_DIR" "${GIT_DIR}"
    wizard_save_state "NGINX_DIR" "${NGINX_DIR}"
    wizard_save_state "BACKUP_DIR" "${BACKUP_DIR}"
    
    # Cache & Quota
    wizard_save_state "CACHE_SIZE" "${CACHE_SIZE}"
    wizard_save_state "DEFAULT_QUOTA_MB" "${DEFAULT_QUOTA_MB}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_1" "${QUOTA_WARN_THRESHOLD_1}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_2" "${QUOTA_WARN_THRESHOLD_2}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_3" "${QUOTA_WARN_THRESHOLD_3}"
    
    # Git
    wizard_save_state "GIT_DEFAULT_BRANCH" "${GIT_DEFAULT_BRANCH}"
    wizard_save_state "AUTOCOMMIT_DELAY" "${AUTOCOMMIT_DELAY}"
    
    # Backup
    wizard_save_state "BACKUP_RETENTION_DAYS" "${BACKUP_RETENTION_DAYS}"
    
    # SSL/TLS
    wizard_save_state "SSL_MODE" "${SSL_MODE}"
    wizard_save_state "LE_EMAIL" "${LE_EMAIL}"
    wizard_save_state "DNS_VERIFIED" "${DNS_VERIFIED}"
    
    # SMTP
    wizard_save_state "SMTP_ENABLED" "${SMTP_ENABLED}"
    wizard_save_state "SMTP_PROFILE" "${SMTP_PROFILE}"
    wizard_save_state "SMTP_HOST" "${SMTP_HOST}"
    wizard_save_state "SMTP_PORT" "${SMTP_PORT}"
    wizard_save_state "SMTP_AUTH" "${SMTP_AUTH}"
    wizard_save_state "SMTP_TLS" "${SMTP_TLS}"
    wizard_save_state "SMTP_USER" "${SMTP_USER}"
    wizard_save_state "SMTP_PASS" "${SMTP_PASS}"
    wizard_save_state "SMTP_FROM" "${SMTP_FROM}"
    wizard_save_state "ALERT_EMAIL" "${ALERT_EMAIL}"
    
    # Gitea
    wizard_save_state "GITEA_VERSION" "${GITEA_VERSION}"
    wizard_save_state "GITEA_ADMIN_USER" "${GITEA_ADMIN_USER}"
    wizard_save_state "GITEA_ADMIN_EMAIL" "${GITEA_ADMIN_EMAIL}"
    wizard_save_state "GITEA_ADMIN_PASS" "${GITEA_ADMIN_PASS}"
    wizard_save_state "GITEA_SECRET_KEY" "${GITEA_SECRET_KEY}"
    wizard_save_state "GITEA_INTERNAL_TOKEN" "${GITEA_INTERNAL_TOKEN}"
    wizard_save_state "GITEA_JWT_SECRET" "${GITEA_JWT_SECRET}"
    
    # Mark all steps as complete
    wizard_complete_step "step1-domains"
    wizard_complete_step "step2-sftp"
    wizard_complete_step "step3-smtp"
    wizard_complete_step "step4-letsencrypt"
    wizard_complete_step "step5-paths"
    wizard_complete_step "step6-gitea-admin"
    wizard_complete_step "step7-summary"
    
    wizard_save_state "WIZARD_COMPLETED" "true"
    wizard_save_state "WIZARD_COMPLETED_AT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log "✓ Configuration saved to wizard state"
    
    return 0
}

################################################################################
# USAGE EXAMPLE
################################################################################

print_usage_example() {
    cat << 'EOF'
################################################################################
# Unattended Installation Example
################################################################################

# Required variables
export CDN_DOMAIN="cdn.example.com"
export GITEA_DOMAIN="git.example.com"
export GITEA_ADMIN_USER="cdnadmin"
export GITEA_ADMIN_EMAIL="admin@example.com"
export GITEA_ADMIN_PASS="SecurePassword123!"

# Optional - Network
export SFTP_PORT="22"

# Optional - Paths
export BASE_DIR="/srv/cdn"
export CACHE_SIZE="10g"

# Optional - Quota
export DEFAULT_QUOTA_MB="5120"
export QUOTA_WARN_THRESHOLD_1="70"
export QUOTA_WARN_THRESHOLD_2="80"
export QUOTA_WARN_THRESHOLD_3="90"

# Optional - SSL
export SSL_MODE="letsencrypt"
export LE_EMAIL="admin@example.com"

# Optional - SMTP
export SMTP_ENABLED="true"
export SMTP_HOST="smtp.gmail.com"
export SMTP_PORT="587"
export SMTP_USER="your-email@gmail.com"
export SMTP_PASS="your-app-password"
export SMTP_FROM="cdn-system@example.com"
export ALERT_EMAIL="admin@example.com"
export SMTP_AUTH="plain"
export SMTP_TLS="starttls"

# Optional - Git
export GIT_DEFAULT_BRANCH="main"
export AUTOCOMMIT_DELAY="60"

# Optional - Backup
export BACKUP_RETENTION_DAYS="30"

# Run unattended installation
sudo -E /opt/scripts/cdn/cdn-initial-setup.sh --unattended

################################################################################
EOF
}

################################################################################
# SELF-TEST MODE
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Multi-Tenant CDN - Configuration from Environment Variables"
    echo "Version: 2.0.0"
    echo ""
    echo "This script is meant to be sourced by cdn-initial-setup.sh"
    echo ""
    echo "Usage Example:"
    echo ""
    print_usage_example
    exit 0
fi

################################################################################
# END OF FILE
################################################################################
