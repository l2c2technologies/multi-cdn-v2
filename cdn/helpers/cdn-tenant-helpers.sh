#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Tenant Helper Functions
# File: /opt/scripts/cdn/helpers/cdn-tenant-helpers.sh
# Phase: 2
# Purpose: Core tenant CRUD operations with full lifecycle management
#
# Dependencies:
#   - /opt/scripts/cdn/helpers/cdn-email-templates.sh (Phase 1)
#   - /opt/scripts/cdn/helpers/cdn-gitea-functions.sh (Phase 2)
#   - /opt/scripts/cdn/helpers/cdn-quota-functions.sh (Phase 2)
#   - /opt/scripts/cdn/helpers/cdn-autocommit.sh (Phase 3 - stub reference)
#
# Features:
#   - Full CRUD: Create, Read, Update, Delete tenants
#   - Automatic rollback on failures with detailed logging
#   - Dry-run mode for safe testing
#   - Strict tenant name validation (lowercase, 3-20 chars, alphanumeric+hyphen+underscore)
#   - Email notifications for all lifecycle events (with admin CC)
#   - SSH key management and rotation
#   - Soft disable/enable functionality
#   - Integration with Gitea (admin-owned repos + read-only tenant collaborators)
#
################################################################################

set -euo pipefail

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDN_BASE_DIR="/opt/scripts/cdn"

# Source dependencies
source "${SCRIPT_DIR}/cdn-email-templates.sh" || {
    echo "ERROR: Failed to source cdn-email-templates.sh" >&2
    exit 1
}

# Global configuration paths
CDN_CONFIG_DIR="/etc/cdn"
CDN_DATA_DIR="/srv/cdn"
CDN_SFTP_DIR="${CDN_DATA_DIR}/sftp"
CDN_GIT_DIR="${CDN_DATA_DIR}/git"
CDN_WWW_DIR="${CDN_DATA_DIR}/www"
CDN_BACKUP_DIR="${CDN_DATA_DIR}/backups"
CDN_LOG_DIR="/var/log/cdn"
CDN_TENANT_DB="${CDN_CONFIG_DIR}/tenants"

# Tenant validation constraints
TENANT_NAME_MIN_LENGTH=3
TENANT_NAME_MAX_LENGTH=20
TENANT_NAME_PATTERN='^[a-z0-9_-]+$'  # Lowercase alphanumeric + hyphen + underscore

# SFTP user ID range (to avoid conflicts with system users)
SFTP_UID_START=5000
SFTP_UID_END=9999

# Default quota (100MB in KB)
DEFAULT_QUOTA_KB=102400

# Dry-run mode flag (set by calling script)
DRY_RUN=${DRY_RUN:-false}

################################################################################
# Logging and Output Functions
################################################################################

log() {
    local msg="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${msg}" | tee -a "${CDN_LOG_DIR}/tenant-operations.log"
}

info() {
    log "$1" "INFO"
}

warn() {
    log "$1" "WARNING"
}

error() {
    log "$1" "ERROR" >&2
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "$1" "DEBUG"
    fi
}

dry_run_msg() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $1"
    fi
}

################################################################################
# Tenant Name Validation
################################################################################

tenant_validate_name() {
    local tenant_name="$1"
    
    # Check length
    local name_length=${#tenant_name}
    if [[ ${name_length} -lt ${TENANT_NAME_MIN_LENGTH} ]]; then
        error "Tenant name '${tenant_name}' too short (minimum ${TENANT_NAME_MIN_LENGTH} chars)"
        return 1
    fi
    
    if [[ ${name_length} -gt ${TENANT_NAME_MAX_LENGTH} ]]; then
        error "Tenant name '${tenant_name}' too long (maximum ${TENANT_NAME_MAX_LENGTH} chars)"
        return 1
    fi
    
    # Check pattern: lowercase alphanumeric + hyphen + underscore
    if [[ ! "${tenant_name}" =~ ${TENANT_NAME_PATTERN} ]]; then
        error "Tenant name '${tenant_name}' contains invalid characters"
        error "Allowed: lowercase letters, numbers, hyphen (-), underscore (_)"
        return 1
    fi
    
    # Check if starts/ends with hyphen or underscore
    if [[ "${tenant_name}" =~ ^[-_] ]] || [[ "${tenant_name}" =~ [-_]$ ]]; then
        error "Tenant name cannot start or end with hyphen or underscore"
        return 1
    fi
    
    # Check for consecutive special characters
    if [[ "${tenant_name}" =~ ([-_]){2,} ]]; then
        error "Tenant name cannot contain consecutive hyphens or underscores"
        return 1
    fi
    
    # Reserved names check
    local reserved_names=("admin" "root" "system" "test" "www" "git" "cdn" "api" "backup")
    for reserved in "${reserved_names[@]}"; do
        if [[ "${tenant_name}" == "${reserved}" ]]; then
            error "Tenant name '${tenant_name}' is reserved"
            return 1
        fi
    done
    
    debug "Tenant name '${tenant_name}' passed validation"
    return 0
}

################################################################################
# Tenant Existence Checks
################################################################################

tenant_exists() {
    local tenant_name="$1"
    
    # Check if tenant directory exists
    if [[ -d "${CDN_TENANT_DB}/${tenant_name}" ]]; then
        return 0
    fi
    
    return 1
}

tenant_get_config_file() {
    local tenant_name="$1"
    echo "${CDN_TENANT_DB}/${tenant_name}/config.env"
}

tenant_get_config() {
    local tenant_name="$1"
    local config_file
    config_file=$(tenant_get_config_file "${tenant_name}")
    
    if [[ ! -f "${config_file}" ]]; then
        error "Tenant config not found: ${config_file}"
        return 1
    fi
    
    cat "${config_file}"
    return 0
}

tenant_load_config() {
    local tenant_name="$1"
    local config_file
    config_file=$(tenant_get_config_file "${tenant_name}")
    
    if [[ ! -f "${config_file}" ]]; then
        error "Cannot load config for tenant '${tenant_name}': config file not found"
        return 1
    fi
    
    source "${config_file}"
    debug "Loaded config for tenant '${tenant_name}'"
    return 0
}

################################################################################
# SFTP User Management
################################################################################

sftp_get_next_uid() {
    # Find next available UID in range
    local next_uid=${SFTP_UID_START}
    
    while [[ ${next_uid} -le ${SFTP_UID_END} ]]; do
        if ! id -u ${next_uid} >/dev/null 2>&1; then
            echo ${next_uid}
            return 0
        fi
        ((next_uid++))
    done
    
    error "No available UIDs in range ${SFTP_UID_START}-${SFTP_UID_END}"
    return 1
}

sftp_generate_password() {
    # Generate secure 20-character password
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 20
}

sftp_create_user() {
    local tenant_name="$1"
    local tenant_email="$2"
    local sftp_password="$3"
    local uid="$4"
    
    local sftp_username="sftp_${tenant_name}"
    local home_dir="${CDN_SFTP_DIR}/${tenant_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would create SFTP user: ${sftp_username} (UID: ${uid})"
        dry_run_msg "Home directory: ${home_dir}"
        return 0
    fi
    
    # Create SFTP group if not exists
    if ! getent group sftpusers >/dev/null; then
        groupadd sftpusers
        info "Created SFTP group: sftpusers"
    fi
    
    # Create user
    useradd -u ${uid} \
            -g sftpusers \
            -d "${home_dir}" \
            -s /bin/false \
            -c "SFTP user for ${tenant_name} (${tenant_email})" \
            "${sftp_username}"
    
    # Set password
    echo "${sftp_username}:${sftp_password}" | chpasswd
    
    info "Created SFTP user: ${sftp_username} (UID: ${uid})"
    return 0
}

sftp_setup_chroot() {
    local tenant_name="$1"
    local home_dir="${CDN_SFTP_DIR}/${tenant_name}"
    local upload_dir="${home_dir}/uploads"
    local sftp_username="sftp_${tenant_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would setup chroot jail: ${home_dir}"
        return 0
    fi
    
    # Create directory structure
    # Root must be owned by root:root with 755 for chroot
    mkdir -p "${home_dir}"
    chown root:root "${home_dir}"
    chmod 755 "${home_dir}"
    
    # Create uploads directory (where user can actually write)
    mkdir -p "${upload_dir}"
    chown "${sftp_username}:sftpusers" "${upload_dir}"
    chmod 755 "${upload_dir}"
    
    info "Setup chroot jail for: ${tenant_name}"
    return 0
}

sftp_delete_user() {
    local tenant_name="$1"
    local sftp_username="sftp_${tenant_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would delete SFTP user: ${sftp_username}"
        return 0
    fi
    
    if id "${sftp_username}" >/dev/null 2>&1; then
        userdel -r "${sftp_username}" 2>/dev/null || true
        info "Deleted SFTP user: ${sftp_username}"
    else
        warn "SFTP user not found: ${sftp_username}"
    fi
    
    return 0
}

################################################################################
# SSH Key Management
################################################################################

tenant_rotate_ssh_key() {
    local tenant_name="$1"
    local new_public_key="$2"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would rotate SSH key for tenant: ${tenant_name}"
        return 0
    fi
    
    local sftp_username="sftp_${tenant_name}"
    local home_dir="${CDN_SFTP_DIR}/${tenant_name}"
    local ssh_dir="${home_dir}/.ssh"
    local authorized_keys="${ssh_dir}/authorized_keys"
    
    # Create .ssh directory if not exists
    mkdir -p "${ssh_dir}"
    
    # Write new public key
    echo "${new_public_key}" > "${authorized_keys}"
    
    # Set proper permissions
    chown -R "${sftp_username}:sftpusers" "${ssh_dir}"
    chmod 700 "${ssh_dir}"
    chmod 600 "${authorized_keys}"
    
    info "Rotated SSH key for tenant: ${tenant_name}"
    
    # Send notification email
    tenant_load_config "${tenant_name}"
    send_tenant_email \
        "${tenant_name}" \
        "SSH Key Updated" \
        "Your SSH key has been successfully updated for tenant: ${tenant_name}

New key fingerprint: $(ssh-keygen -lf <(echo "${new_public_key}") 2>/dev/null | awk '{print $2}')

If you did not authorize this change, please contact support immediately." \
        "${LEVEL_INFO}" \
        "ssh-key-rotation" \
        0
    
    return 0
}

################################################################################
# Tenant Configuration Management
################################################################################

tenant_write_config() {
    local tenant_name="$1"
    local tenant_email="$2"
    local sftp_username="$3"
    local sftp_uid="$4"
    local gitea_username="$5"
    local quota_kb="$6"
    local created_at="$7"
    
    local config_dir="${CDN_TENANT_DB}/${tenant_name}"
    local config_file="${config_dir}/config.env"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would write config: ${config_file}"
        return 0
    fi
    
    mkdir -p "${config_dir}"
    
    cat > "${config_file}" << EOF
# Tenant Configuration
# Generated: ${created_at}

TENANT_NAME="${tenant_name}"
TENANT_EMAIL="${tenant_email}"
TENANT_STATUS="active"

# SFTP Configuration
SFTP_USERNAME="${sftp_username}"
SFTP_UID="${sftp_uid}"
SFTP_HOME="${CDN_SFTP_DIR}/${tenant_name}"

# Gitea Configuration
GITEA_USERNAME="${gitea_username}"
GITEA_REPO_OWNER="cdnadmin"
GITEA_REPO_NAME="${tenant_name}"
GITEA_REPO_URL="https://\${GITEA_DOMAIN}/cdnadmin/${tenant_name}"

# Quota Configuration
QUOTA_KB="${quota_kb}"
QUOTA_MB=$((quota_kb / 1024))

# Directories
SFTP_DIR="${CDN_SFTP_DIR}/${tenant_name}"
GIT_WORK_DIR="${CDN_GIT_DIR}/${tenant_name}"
WWW_DIR="${CDN_WWW_DIR}/${tenant_name}"

# Timestamps
CREATED_AT="${created_at}"
UPDATED_AT="${created_at}"
EOF
    
    chmod 600 "${config_file}"
    info "Wrote config for tenant: ${tenant_name}"
    return 0
}

tenant_update_config_field() {
    local tenant_name="$1"
    local field_name="$2"
    local field_value="$3"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    local config_file
    config_file=$(tenant_get_config_file "${tenant_name}")
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would update ${field_name}=${field_value} in ${config_file}"
        return 0
    fi
    
    # Update field in config file
    sed -i "s|^${field_name}=.*|${field_name}=\"${field_value}\"|" "${config_file}"
    
    # Update timestamp
    sed -i "s|^UPDATED_AT=.*|UPDATED_AT=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"|" "${config_file}"
    
    debug "Updated ${field_name} for tenant: ${tenant_name}"
    return 0
}

################################################################################
# Tenant Update Operations
################################################################################

tenant_update_email() {
    local tenant_name="$1"
    local new_email="$2"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    # Validate email format
    if [[ ! "${new_email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: ${new_email}"
        return 1
    fi
    
    info "Updating email for tenant '${tenant_name}': ${new_email}"
    
    tenant_update_config_field "${tenant_name}" "TENANT_EMAIL" "${new_email}"
    
    # Send confirmation to both old and new email
    send_tenant_email \
        "${tenant_name}" \
        "Contact Email Updated" \
        "Your contact email for tenant '${tenant_name}' has been updated to: ${new_email}

If you did not request this change, please contact support immediately." \
        "${LEVEL_INFO}" \
        "email-update" \
        0
    
    return 0
}

tenant_update_quota() {
    local tenant_name="$1"
    local new_quota_kb="$2"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    # Validate quota is a positive integer
    if ! [[ "${new_quota_kb}" =~ ^[0-9]+$ ]] || [[ ${new_quota_kb} -le 0 ]]; then
        error "Invalid quota: ${new_quota_kb} (must be positive integer KB)"
        return 1
    fi
    
    info "Updating quota for tenant '${tenant_name}': ${new_quota_kb} KB"
    
    tenant_update_config_field "${tenant_name}" "QUOTA_KB" "${new_quota_kb}"
    tenant_update_config_field "${tenant_name}" "QUOTA_MB" "$((new_quota_kb / 1024))"
    
    # Send notification
    tenant_load_config "${tenant_name}"
    send_tenant_email \
        "${tenant_name}" \
        "Storage Quota Updated" \
        "Your storage quota for tenant '${tenant_name}' has been updated to: $((new_quota_kb / 1024)) MB

You can check your current usage anytime via SFTP or the Gitea web interface." \
        "${LEVEL_INFO}" \
        "quota-update" \
        0
    
    return 0
}

tenant_update_git_user() {
    local tenant_name="$1"
    local git_user_name="$2"
    local git_user_email="$3"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    info "Updating Git user details for tenant '${tenant_name}'"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would update Git user: ${git_user_name} <${git_user_email}>"
        return 0
    fi
    
    local git_work_dir="${CDN_GIT_DIR}/${tenant_name}"
    
    if [[ -d "${git_work_dir}" ]]; then
        cd "${git_work_dir}"
        git config user.name "${git_user_name}"
        git config user.email "${git_user_email}"
        info "Updated Git config for: ${tenant_name}"
    else
        warn "Git work directory not found: ${git_work_dir}"
    fi
    
    return 0
}

################################################################################
# Tenant Enable/Disable
################################################################################

tenant_disable() {
    local tenant_name="$1"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    info "Disabling tenant: ${tenant_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would disable tenant: ${tenant_name}"
        return 0
    fi
    
    # Update status in config
    tenant_update_config_field "${tenant_name}" "TENANT_STATUS" "disabled"
    
    # Lock SFTP account
    local sftp_username="sftp_${tenant_name}"
    if id "${sftp_username}" >/dev/null 2>&1; then
        passwd -l "${sftp_username}" >/dev/null 2>&1
        info "Locked SFTP account: ${sftp_username}"
    fi
    
    # Send notification
    tenant_load_config "${tenant_name}"
    send_tenant_email \
        "${tenant_name}" \
        "Account Disabled" \
        "Your CDN tenant account '${tenant_name}' has been disabled.

SFTP access: LOCKED
Gitea access: READ-ONLY (unchanged)
CDN content: STILL AVAILABLE

To re-enable your account, please contact support." \
        "${LEVEL_WARNING}" \
        "account-disabled" \
        0
    
    return 0
}

tenant_enable() {
    local tenant_name="$1"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    info "Enabling tenant: ${tenant_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        dry_run_msg "Would enable tenant: ${tenant_name}"
        return 0
    fi
    
    # Update status in config
    tenant_update_config_field "${tenant_name}" "TENANT_STATUS" "active"
    
    # Unlock SFTP account
    local sftp_username="sftp_${tenant_name}"
    if id "${sftp_username}" >/dev/null 2>&1; then
        passwd -u "${sftp_username}" >/dev/null 2>&1
        info "Unlocked SFTP account: ${sftp_username}"
    fi
    
    # Send notification
    tenant_load_config "${tenant_name}"
    send_tenant_email \
        "${tenant_name}" \
        "Account Re-enabled" \
        "Your CDN tenant account '${tenant_name}' has been re-enabled.

SFTP access: UNLOCKED
Gitea access: READ-ONLY
CDN content: AVAILABLE

You can now upload content via SFTP." \
        "${LEVEL_INFO}" \
        "account-enabled" \
        0
    
    return 0
}

################################################################################
# Tenant Information Display
################################################################################

tenant_info() {
    local tenant_name="$1"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    tenant_load_config "${tenant_name}"
    
    echo "=== Tenant Information: ${TENANT_NAME} ==="
    echo ""
    echo "Status:        ${TENANT_STATUS}"
    echo "Email:         ${TENANT_EMAIL}"
    echo "Created:       ${CREATED_AT}"
    echo "Last Updated:  ${UPDATED_AT}"
    echo ""
    echo "--- SFTP Access ---"
    echo "Username:      ${SFTP_USERNAME}"
    echo "UID:           ${SFTP_UID}"
    echo "Home:          ${SFTP_HOME}"
    echo ""
    echo "--- Gitea Access ---"
    echo "Username:      ${GITEA_USERNAME}"
    echo "Repository:    ${GITEA_REPO_URL}"
    echo "Access:        READ-ONLY"
    echo ""
    echo "--- Storage ---"
    echo "Quota:         ${QUOTA_MB} MB (${QUOTA_KB} KB)"
    
    # Get current usage (will source cdn-quota-functions.sh when available)
    if declare -f quota_get_usage >/dev/null 2>&1; then
        local usage_kb
        usage_kb=$(quota_get_usage "${tenant_name}")
        local usage_mb=$((usage_kb / 1024))
        local usage_percent=$((usage_kb * 100 / QUOTA_KB))
        echo "Current Usage: ${usage_mb} MB (${usage_percent}%)"
    fi
    
    echo ""
    echo "--- Directories ---"
    echo "SFTP:          ${SFTP_DIR}"
    echo "Git Work:      ${GIT_WORK_DIR}"
    echo "WWW:           ${WWW_DIR}"
    echo ""
    
    return 0
}

tenant_list() {
    local status_filter="${1:-all}"  # all, active, disabled
    
    if [[ ! -d "${CDN_TENANT_DB}" ]]; then
        warn "No tenants found (database directory does not exist)"
        return 0
    fi
    
    echo "=== CDN Tenants ==="
    echo ""
    printf "%-20s %-10s %-30s %-15s\n" "TENANT" "STATUS" "EMAIL" "QUOTA (MB)"
    printf "%-20s %-10s %-30s %-15s\n" "------" "------" "-----" "----------"
    
    local count=0
    for tenant_dir in "${CDN_TENANT_DB}"/*; do
        if [[ ! -d "${tenant_dir}" ]]; then
            continue
        fi
        
        local tenant_name
        tenant_name=$(basename "${tenant_dir}")
        
        if ! tenant_load_config "${tenant_name}" 2>/dev/null; then
            continue
        fi
        
        # Apply status filter
        if [[ "${status_filter}" != "all" ]] && [[ "${TENANT_STATUS}" != "${status_filter}" ]]; then
            continue
        fi
        
        printf "%-20s %-10s %-30s %-15s\n" \
            "${TENANT_NAME}" \
            "${TENANT_STATUS}" \
            "${TENANT_EMAIL}" \
            "${QUOTA_MB}"
        
        ((count++))
    done
    
    echo ""
    echo "Total: ${count} tenant(s)"
    
    return 0
}

################################################################################
# Tenant Creation with Rollback
################################################################################

tenant_create_rollback() {
    local tenant_name="$1"
    local rollback_log="$2"
    
    warn "Rolling back tenant creation for: ${tenant_name}"
    
    # Read rollback steps from log
    if [[ -f "${rollback_log}" ]]; then
        while IFS= read -r line; do
            if [[ "${line}" =~ ^ROLLBACK: ]]; then
                local action="${line#ROLLBACK: }"
                warn "Executing rollback: ${action}"
                eval "${action}" 2>&1 | tee -a "${rollback_log}"
            fi
        done < "${rollback_log}"
    fi
    
    # Cleanup tenant database entry
    if [[ -d "${CDN_TENANT_DB}/${tenant_name}" ]]; then
        rm -rf "${CDN_TENANT_DB}/${tenant_name}"
        warn "Removed tenant database entry: ${tenant_name}"
    fi
    
    warn "Rollback completed for: ${tenant_name}"
}

tenant_create() {
    local tenant_name="$1"
    local tenant_email="$2"
    local quota_kb="${3:-${DEFAULT_QUOTA_KB}}"
    
    # Validation
    if ! tenant_validate_name "${tenant_name}"; then
        return 1
    fi
    
    if tenant_exists "${tenant_name}"; then
        error "Tenant already exists: ${tenant_name}"
        return 1
    fi
    
    # Validate email
    if [[ ! "${tenant_email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: ${tenant_email}"
        return 1
    fi
    
    info "Creating tenant: ${tenant_name}"
    
    # Setup rollback logging
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local rollback_log="${CDN_LOG_DIR}/rollback-${tenant_name}-${timestamp}.log"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "${CDN_LOG_DIR}"
        echo "=== Rollback Log for ${tenant_name} ===" > "${rollback_log}"
        echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${rollback_log}"
    fi
    
    # Generate credentials
    local sftp_password
    sftp_password=$(sftp_generate_password)
    local gitea_password
    gitea_password=$(gitea_generate_password)  # From cdn-gitea-functions.sh
    
    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Step 1: Get next available SFTP UID
    info "Step 1/10: Allocating SFTP UID"
    local sftp_uid
    sftp_uid=$(sftp_get_next_uid) || {
        error "Failed to allocate SFTP UID"
        return 1
    }
    echo "ROLLBACK: # UID allocation has no rollback" >> "${rollback_log}"
    
    # Step 2: Create SFTP user
    info "Step 2/10: Creating SFTP user"
    if ! sftp_create_user "${tenant_name}" "${tenant_email}" "${sftp_password}" "${sftp_uid}"; then
        error "Failed to create SFTP user"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    echo "ROLLBACK: sftp_delete_user '${tenant_name}'" >> "${rollback_log}"
    
    # Step 3: Setup SFTP chroot jail
    info "Step 3/10: Setting up SFTP chroot"
    if ! sftp_setup_chroot "${tenant_name}"; then
        error "Failed to setup SFTP chroot"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    echo "ROLLBACK: rm -rf '${CDN_SFTP_DIR}/${tenant_name}'" >> "${rollback_log}"
    
    # Step 4: Create Gitea repository
    info "Step 4/10: Creating Gitea repository"
    if ! gitea_create_repository "${tenant_name}"; then
        error "Failed to create Gitea repository"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    echo "ROLLBACK: gitea_delete_repository '${tenant_name}'" >> "${rollback_log}"
    
    # Step 5: Create Gitea user account
    info "Step 5/10: Creating Gitea user account"
    local gitea_username="tenant_${tenant_name}"
    if ! gitea_create_user "${gitea_username}" "${tenant_email}" "${gitea_password}"; then
        error "Failed to create Gitea user"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    echo "ROLLBACK: gitea_delete_user '${gitea_username}'" >> "${rollback_log}"
    
    # Step 6: Add tenant as read-only collaborator
    info "Step 6/10: Adding tenant as repository collaborator"
    if ! gitea_add_collaborator "${tenant_name}" "${gitea_username}" "read"; then
        error "Failed to add collaborator"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    echo "ROLLBACK: gitea_remove_collaborator '${tenant_name}' '${gitea_username}'" >> "${rollback_log}"
    
    # Step 7: Initialize repository with README
    info "Step 7/10: Initializing Git repository"
    if ! gitea_initialize_repo "${tenant_name}" "${tenant_email}"; then
        error "Failed to initialize Git repository"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    
    # Step 8: Create www symlink
    info "Step 8/10: Creating www symlink"
    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "${CDN_WWW_DIR}"
        ln -sf "${CDN_SFTP_DIR}/${tenant_name}/uploads" "${CDN_WWW_DIR}/${tenant_name}"
    else
        dry_run_msg "Would create symlink: ${CDN_WWW_DIR}/${tenant_name} -> ${CDN_SFTP_DIR}/${tenant_name}/uploads"
    fi
    echo "ROLLBACK: rm -f '${CDN_WWW_DIR}/${tenant_name}'" >> "${rollback_log}"
    
    # Step 9: Write tenant configuration
    info "Step 9/10: Writing tenant configuration"
    if ! tenant_write_config \
        "${tenant_name}" \
        "${tenant_email}" \
        "sftp_${tenant_name}" \
        "${sftp_uid}" \
        "${gitea_username}" \
        "${quota_kb}" \
        "${created_at}"; then
        error "Failed to write tenant configuration"
        tenant_create_rollback "${tenant_name}" "${rollback_log}"
        return 1
    fi
    
    # Step 10: Send welcome email
    info "Step 10/10: Sending welcome email"
    
    # Generate welcome email content
    local welcome_body
    welcome_body=$(cat << EOF
Welcome to the Multi-Tenant CDN System!

Your account has been successfully created:

=== Account Details ===
Tenant Name: ${tenant_name}
Email: ${tenant_email}
Status: Active
Created: ${created_at}

=== SFTP Access ===
Host: ${SFTP_HOST:-your-cdn-server.com}
Port: ${SFTP_PORT:-22}
Username: sftp_${tenant_name}
Password: ${sftp_password}

Upload your files to the 'uploads' directory via SFTP.
All changes are automatically tracked with Git version control.

=== Gitea Web Portal ===
URL: https://${GITEA_DOMAIN:-git.your-cdn-server.com}
Username: ${gitea_username}
Password: ${gitea_password}
Access: READ-ONLY (view your content history)

=== CDN Delivery ===
Your content will be available at:
https://${CDN_DOMAIN:-cdn.your-cdn-server.com}/${tenant_name}/

=== Storage Quota ===
Allocated: $((quota_kb / 1024)) MB
Current Usage: 0 MB (0%)

=== Quick Start Guide ===
1. Connect via SFTP using the credentials above
2. Upload files to the 'uploads' directory
3. Files are automatically versioned in Git
4. Access your content via the CDN URL
5. Monitor your uploads via the Gitea web portal

=== Support ===
If you have any questions or need assistance, please contact:
${ALERT_EMAIL:-support@your-cdn-server.com}

Thank you for choosing our CDN service!
EOF
)
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        send_tenant_email \
            "${tenant_name}" \
            "Welcome to CDN - Account Created" \
            "${welcome_body}" \
            "${LEVEL_INFO}" \
            "welcome" \
            0
    else
        dry_run_msg "Would send welcome email to: ${tenant_email}"
    fi
    
    info "Successfully created tenant: ${tenant_name}"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${rollback_log}"
    fi
    
    return 0
}

################################################################################
# Tenant Deletion
################################################################################

tenant_delete() {
    local tenant_name="$1"
    local confirm_flag="${2:-}"
    
    if ! tenant_exists "${tenant_name}"; then
        error "Tenant does not exist: ${tenant_name}"
        return 1
    fi
    
    # Require --confirm-delete flag
    if [[ "${confirm_flag}" != "--confirm-delete" ]]; then
        error "Tenant deletion requires --confirm-delete flag for safety"
        error "Usage: tenant_delete ${tenant_name} --confirm-delete"
        return 1
    fi
    
    tenant_load_config "${tenant_name}"
    
    # Prompt for manual backup
    if [[ "${DRY_RUN}" != "true" ]] && [[ -t 0 ]]; then
        echo ""
        warn "You are about to DELETE tenant: ${tenant_name}"
        warn "This will remove:"
        warn "  - SFTP user and data (${SFTP_DIR})"
        warn "  - Gitea user and repository"
        warn "  - WWW symlink"
        warn "  - All configuration"
        echo ""
        read -p "Have you backed up tenant data? (yes/no): " -r backup_confirm
        if [[ "${backup_confirm}" != "yes" ]]; then
            error "Deletion cancelled - please backup tenant data first"
            return 1
        fi
        
        read -p "Type tenant name to confirm deletion: " -r name_confirm
        if [[ "${name_confirm}" != "${tenant_name}" ]]; then
            error "Tenant name mismatch - deletion cancelled"
            return 1
        fi
    fi
    
    info "Deleting tenant: ${tenant_name}"
    
    # Send deletion notification before removing email config
    send_tenant_email \
        "${tenant_name}" \
        "Account Deletion Notice" \
        "Your CDN tenant account '${tenant_name}' has been scheduled for deletion.

All data will be permanently removed:
- SFTP access and uploaded files
- Gitea user and repository
- CDN content

This action cannot be undone.

If you did not request this deletion, please contact support immediately." \
        "${LEVEL_CRITICAL}" \
        "account-deletion" \
        0
    
    # Delete in reverse order of creation
    
    # Remove www symlink
    if [[ -L "${CDN_WWW_DIR}/${tenant_name}" ]] || [[ -e "${CDN_WWW_DIR}/${tenant_name}" ]]; then
        rm -f "${CDN_WWW_DIR}/${tenant_name}"
        info "Removed www symlink"
    fi
    
    # Delete Gitea collaborator access
    if declare -f gitea_remove_collaborator >/dev/null 2>&1; then
        gitea_remove_collaborator "${tenant_name}" "${GITEA_USERNAME}" || true
    fi
    
    # Delete Gitea user
    if declare -f gitea_delete_user >/dev/null 2>&1; then
        gitea_delete_user "${GITEA_USERNAME}" || true
    fi
    
    # Delete Gitea repository
    if declare -f gitea_delete_repository >/dev/null 2>&1; then
        gitea_delete_repository "${tenant_name}" || true
    fi
    
    # Delete SFTP chroot and data
    if [[ -d "${SFTP_DIR}" ]]; then
        rm -rf "${SFTP_DIR}"
        info "Removed SFTP directory: ${SFTP_DIR}"
    fi
    
    # Delete SFTP user
    sftp_delete_user "${tenant_name}"
    
    # Delete tenant configuration
    if [[ -d "${CDN_TENANT_DB}/${tenant_name}" ]]; then
        rm -rf "${CDN_TENANT_DB}/${tenant_name}"
        info "Removed tenant configuration"
    fi
    
    info "Successfully deleted tenant: ${tenant_name}"
    
    return 0
}

################################################################################
# Main (for testing)
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "cdn-tenant-helpers.sh - Tenant Management Helper Functions"
    echo "This script provides functions for other scripts to use."
    echo "It should be sourced, not executed directly."
    echo ""
    echo "Available functions:"
    echo "  - tenant_validate_name <name>"
    echo "  - tenant_exists <name>"
    echo "  - tenant_create <name> <email> [quota_kb]"
    echo "  - tenant_delete <name> --confirm-delete"
    echo "  - tenant_info <name>"
    echo "  - tenant_list [status]"
    echo "  - tenant_enable <name>"
    echo "  - tenant_disable <name>"
    echo "  - tenant_update_email <name> <new_email>"
    echo "  - tenant_update_quota <name> <new_quota_kb>"
    echo "  - tenant_update_git_user <name> <git_name> <git_email>"
    echo "  - tenant_rotate_ssh_key <name> <public_key>"
    exit 1
fi
