#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 5
# Step: Paths and System Configuration
# Location: /opt/scripts/cdn/includes/step5-paths.sh
################################################################################

step5_paths() {
    wizard_header "Paths and System Configuration" "5"
    
    wizard_info_box "System Directories" \
        "The CDN system organizes files in a structured directory layout:

BASE_DIR/
├── sftp/       - SFTP upload directories (chroot jails)
├── git/        - Git repositories (bare)
├── www/        - Nginx-served content (symlinks)
└── backups/    - Automated backups

Additional paths:
• /etc/cdn/     - Configuration files
• /var/log/cdn/ - System logs
• /var/cache/nginx/cdn/ - Nginx cache"
    
    echo ""
    
    # ============================================================================
    # Base Directory
    # ============================================================================
    
    local base_dir=""
    local default_base="${BASE_DIR:-/srv/cdn}"
    
    info "Base Directory Configuration"
    echo ""
    echo "The base directory contains all CDN data (SFTP, Git, www, backups)."
    echo "Ensure this location has sufficient disk space."
    echo ""
    
    wizard_example "Base Directory" \
        "/srv/cdn (default)" \
        "/data/cdn" \
        "/var/lib/cdn" \
        "/mnt/storage/cdn"
    
    echo ""
    
    while true; do
        base_dir=$(prompt_input "Base directory" "${default_base}" "" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get base directory"
            return 1
        fi
        
        # Validate path format (absolute path)
        if [[ ! "${base_dir}" =~ ^/ ]]; then
            error "Base directory must be an absolute path (start with /)"
            continue
        fi
        
        # Check if path exists
        if [[ -d "${base_dir}" ]]; then
            warn "Directory already exists: ${base_dir}"
            
            # Check if it's empty
            if [[ -n "$(ls -A "${base_dir}" 2>/dev/null)" ]]; then
                warn "Directory is not empty!"
                
                if ! prompt_confirm "Use this directory anyway? (contents will be preserved)" "no"; then
                    continue
                fi
            else
                log "✓ Directory exists and is empty"
            fi
        else
            info "Directory will be created: ${base_dir}"
        fi
        
        # Check parent directory is writable
        local parent_dir
        parent_dir="$(dirname "${base_dir}")"
        
        if [[ ! -d "${parent_dir}" ]]; then
            warn "Parent directory does not exist: ${parent_dir}"
            
            if ! prompt_confirm "Create parent directory?" "yes"; then
                continue
            fi
        elif [[ ! -w "${parent_dir}" ]]; then
            error "Parent directory is not writable: ${parent_dir}"
            continue
        fi
        
        # Show disk space
        local disk_space
        if [[ -d "${parent_dir}" ]]; then
            disk_space=$(df -h "${parent_dir}" 2>/dev/null | tail -n1 | awk '{print $4}')
            log "Available space on filesystem: ${disk_space}"
        fi
        
        # Show subdirectories
        echo ""
        echo -e "${COLOR_GREEN}Directory structure:${COLOR_NC}"
        echo "  ${base_dir}/"
        echo "  ├── sftp/      - SFTP uploads"
        echo "  ├── git/       - Git repositories"
        echo "  ├── www/       - Web content"
        echo "  └── backups/   - Backups"
        echo ""
        
        if prompt_confirm "Use this base directory?" "yes"; then
            break
        fi
    done
    
    # ============================================================================
    # Nginx Cache Size
    # ============================================================================
    
    echo ""
    info "Nginx Cache Configuration"
    echo ""
    echo "The CDN uses Nginx caching to improve performance."
    echo "Cache size should be based on available disk space."
    echo ""
    
    wizard_example "Cache Size" \
        "10g (default - 10 GB)" \
        "5g (small deployments)" \
        "50g (medium deployments)" \
        "100g (large deployments)"
    
    echo ""
    
    local cache_size=""
    local default_cache="${CACHE_SIZE:-10g}"
    
    while true; do
        cache_size=$(prompt_input "Nginx cache size" "${default_cache}" "" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get cache size"
            return 1
        fi
        
        # Validate format (number + unit: k, m, g, t)
        if [[ ! "${cache_size}" =~ ^[0-9]+[kmgtKMGT]$ ]]; then
            error "Invalid cache size format. Use format: 10g, 500m, 50g, etc."
            warn "Valid units: k (KB), m (MB), g (GB), t (TB)"
            continue
        fi
        
        # Convert to human-readable and warn if very large
        local size_num="${cache_size//[^0-9]/}"
        local size_unit="${cache_size//[0-9]/}"
        size_unit="${size_unit,,}"  # lowercase
        
        case "${size_unit}" in
            k)
                if [[ ${size_num} -gt 1000000 ]]; then
                    warn "Cache size is very large: ${cache_size}"
                fi
                ;;
            m)
                if [[ ${size_num} -gt 100000 ]]; then
                    warn "Cache size is very large: ${cache_size}"
                fi
                ;;
            g)
                if [[ ${size_num} -gt 1000 ]]; then
                    warn "Cache size is very large: ${cache_size}"
                fi
                log "Cache size: ${cache_size} (${size_num} GB)"
                ;;
            t)
                warn "Cache size in terabytes: ${cache_size}"
                log "Ensure sufficient disk space available"
                ;;
        esac
        
        echo ""
        if prompt_confirm "Use cache size of ${cache_size}?" "yes"; then
            break
        fi
    done
    
    # ============================================================================
    # Backup Retention
    # ============================================================================
    
    echo ""
    info "Backup Retention Configuration"
    echo ""
    echo "Automated backups will be created daily."
    echo "Old backups are automatically deleted after retention period."
    echo ""
    
    wizard_example "Retention Period" \
        "30 (default - 30 days)" \
        "7 (1 week)" \
        "14 (2 weeks)" \
        "90 (3 months)" \
        "180 (6 months)"
    
    echo ""
    
    local backup_retention=""
    local default_retention="${BACKUP_RETENTION_DAYS:-30}"
    
    while true; do
        backup_retention=$(prompt_input "Backup retention (days)" "${default_retention}" "validate_positive_integer" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get backup retention"
            continue
        fi
        
        # Validate it's a positive integer
        if ! [[ "${backup_retention}" =~ ^[0-9]+$ ]] || [[ ${backup_retention} -lt 1 ]]; then
            error "Backup retention must be a positive integer (days)"
            continue
        fi
        
        # Warn if very short or very long
        if [[ ${backup_retention} -lt 7 ]]; then
            warn "Short retention period: ${backup_retention} days"
            warn "Backups will be deleted quickly"
        elif [[ ${backup_retention} -gt 365 ]]; then
            warn "Long retention period: ${backup_retention} days (${$((backup_retention / 365))} year(s))"
            warn "Backups will consume significant disk space"
        fi
        
        log "Backups will be kept for ${backup_retention} days"
        
        echo ""
        if prompt_confirm "Use retention period of ${backup_retention} days?" "yes"; then
            break
        fi
    done
    
    # ============================================================================
    # Additional Configuration (with defaults)
    # ============================================================================
    
    echo ""
    info "Additional Configuration"
    echo ""
    
    # Default Quota
    local default_quota=""
    local default_quota_value="${DEFAULT_QUOTA_MB:-5120}"
    
    echo "Default quota for new tenants (MB):"
    echo "  Current: ${default_quota_value} MB (5 GB)"
    echo ""
    
    if prompt_confirm "Use default quota of ${default_quota_value} MB?" "yes"; then
        default_quota="${default_quota_value}"
    else
        while true; do
            default_quota=$(prompt_input "Default tenant quota (MB)" "${default_quota_value}" "" "false" "false")
            
            if [[ "${default_quota}" =~ ^[0-9]+$ ]] && [[ ${default_quota} -gt 0 ]]; then
                log "Default quota: ${default_quota} MB ($((default_quota / 1024)) GB)"
                break
            fi
            
            error "Quota must be a positive integer (MB)"
        done
    fi
    
    # Quota Warning Thresholds
    echo ""
    local quota_warn_1="${QUOTA_WARN_THRESHOLD_1:-70}"
    local quota_warn_2="${QUOTA_WARN_THRESHOLD_2:-80}"
    local quota_warn_3="${QUOTA_WARN_THRESHOLD_3:-90}"
    
    echo "Quota warning thresholds (% of quota):"
    echo "  First warning:  ${quota_warn_1}%"
    echo "  Second warning: ${quota_warn_2}%"
    echo "  Critical:       ${quota_warn_3}%"
    echo ""
    
    if ! prompt_confirm "Use these default warning thresholds?" "yes"; then
        echo ""
        quota_warn_1=$(prompt_input "First warning threshold (%)" "${quota_warn_1}" "" "false" "false")
        quota_warn_2=$(prompt_input "Second warning threshold (%)" "${quota_warn_2}" "" "false" "false")
        quota_warn_3=$(prompt_input "Critical threshold (%)" "${quota_warn_3}" "" "false" "false")
    fi
    
    # Git Configuration
    echo ""
    local git_branch="${GIT_DEFAULT_BRANCH:-main}"
    local autocommit_delay="${AUTOCOMMIT_DELAY:-60}"
    
    echo "Git configuration:"
    echo "  Default branch: ${git_branch}"
    echo "  Auto-commit delay: ${autocommit_delay}s"
    echo ""
    
    if ! prompt_confirm "Use these default Git settings?" "yes"; then
        echo ""
        git_branch=$(prompt_input "Default Git branch name" "${git_branch}" "" "false" "false")
        autocommit_delay=$(prompt_input "Auto-commit delay (seconds)" "${autocommit_delay}" "" "false" "false")
    fi
    
    # ============================================================================
    # Configuration Summary
    # ============================================================================
    
    echo ""
    wizard_info_box "System Configuration Summary" \
        "Base Directory: ${base_dir}
  ├── ${base_dir}/sftp
  ├── ${base_dir}/git
  ├── ${base_dir}/www
  └── ${base_dir}/backups

Cache: ${cache_size} in /var/cache/nginx/cdn
Backups: Keep for ${backup_retention} days
Default Quota: ${default_quota} MB per tenant
Thresholds: ${quota_warn_1}%, ${quota_warn_2}%, ${quota_warn_3}%
Git: Branch '${git_branch}', auto-commit after ${autocommit_delay}s"
    
    if ! prompt_confirm "Confirm these settings?"; then
        warn "Configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step5_paths  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Save Configuration
    # ============================================================================
    
    # Derived paths
    local sftp_dir="${base_dir}/sftp"
    local git_dir="${base_dir}/git"
    local nginx_dir="${base_dir}/www"
    local backup_dir="${base_dir}/backups"
    
    wizard_save_state "BASE_DIR" "${base_dir}"
    wizard_save_state "SFTP_DIR" "${sftp_dir}"
    wizard_save_state "GIT_DIR" "${git_dir}"
    wizard_save_state "NGINX_DIR" "${nginx_dir}"
    wizard_save_state "BACKUP_DIR" "${backup_dir}"
    wizard_save_state "CACHE_SIZE" "${cache_size}"
    wizard_save_state "BACKUP_RETENTION_DAYS" "${backup_retention}"
    wizard_save_state "DEFAULT_QUOTA_MB" "${default_quota}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_1" "${quota_warn_1}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_2" "${quota_warn_2}"
    wizard_save_state "QUOTA_WARN_THRESHOLD_3" "${quota_warn_3}"
    wizard_save_state "GIT_DEFAULT_BRANCH" "${git_branch}"
    wizard_save_state "AUTOCOMMIT_DELAY" "${autocommit_delay}"
    
    # Export for use in other steps
    export BASE_DIR="${base_dir}"
    export SFTP_DIR="${sftp_dir}"
    export GIT_DIR="${git_dir}"
    export NGINX_DIR="${nginx_dir}"
    export BACKUP_DIR="${backup_dir}"
    export CACHE_SIZE="${cache_size}"
    export BACKUP_RETENTION_DAYS="${backup_retention}"
    export DEFAULT_QUOTA_MB="${default_quota}"
    export GIT_DEFAULT_BRANCH="${git_branch}"
    export AUTOCOMMIT_DELAY="${autocommit_delay}"
    
    log "✓ Paths and system configuration completed"
    log "  Base: ${base_dir}"
    log "  Cache: ${cache_size}"
    log "  Retention: ${backup_retention} days"
    log "  Default Quota: ${default_quota} MB"
    
    wizard_complete_step "step5-paths"
    
    wizard_footer
    echo "Press ENTER to continue to next step..."
    read -r
    
    return 0
}

# Self-test when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source dependencies
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/common.sh"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/wizard-common.sh"
    
    # Initialize wizard
    wizard_init
    
    # Mock previous steps
    export CDN_DOMAIN="cdn.example.com"
    export GITEA_DOMAIN="git.example.com"
    
    # Run step
    step5_paths
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^(BASE_DIR|CACHE_SIZE|BACKUP_RETENTION|QUOTA)=" "${WIZARD_STATE_FILE}"
fi
