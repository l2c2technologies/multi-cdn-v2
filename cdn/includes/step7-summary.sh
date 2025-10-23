#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 7
# Step: Configuration Summary and Final Confirmation
# Location: /opt/scripts/cdn/includes/step7-summary.sh
################################################################################

step7_summary() {
    wizard_header "Configuration Summary" "7"
    
    wizard_info_box "Final Review" \
        "This is your last chance to review the complete configuration before proceeding with installation.

You can:
• Review all settings
• Export configuration to a file
• Edit individual settings by going back to specific steps
• Confirm and proceed with installation"
    
    echo ""
    
    # ============================================================================
    # Display Complete Configuration
    # ============================================================================
    
    local show_full_summary=true
    
    while true; do
        if [[ "${show_full_summary}" == true ]]; then
            clear
            wizard_header "Configuration Summary" "7"
            
            echo -e "${COLOR_GREEN}╔═══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
            echo -e "${COLOR_GREEN}║                   COMPLETE CONFIGURATION SUMMARY                  ║${COLOR_NC}"
            echo -e "${COLOR_GREEN}╚═══════════════════════════════════════════════════════════════════╝${COLOR_NC}"
            echo ""
            
            # Domain Configuration
            echo -e "${COLOR_CYAN}━━━ Domain Configuration (Step 1) ━━━${COLOR_NC}"
            echo "  CDN Domain:         ${CDN_DOMAIN}"
            echo "  Gitea Domain:       ${GITEA_DOMAIN}"
            echo ""
            
            # SFTP Configuration
            echo -e "${COLOR_CYAN}━━━ SFTP Configuration (Step 2) ━━━${COLOR_NC}"
            echo "  SFTP Port:          ${SFTP_PORT}"
            echo "  SSH Port:           ${SSH_PORT}"
            if [[ "${SFTP_PORT}" != "${SSH_PORT}" ]]; then
                echo -e "  ${COLOR_YELLOW}⚠ WARNING: SFTP and SSH ports differ - manual SSH config required${COLOR_NC}"
            fi
            echo ""
            
            # SMTP Configuration
            echo -e "${COLOR_CYAN}━━━ Email Configuration (Step 3) ━━━${COLOR_NC}"
            if [[ "${SMTP_ENABLED}" == "true" ]]; then
                echo "  Status:             Enabled"
                echo "  Profile:            ${SMTP_PROFILE}"
                echo "  SMTP Host:          ${SMTP_HOST}"
                echo "  SMTP Port:          ${SMTP_PORT}"
                echo "  SMTP User:          ${SMTP_USER}"
                echo "  SMTP Password:      [HIDDEN]"
                echo "  From Address:       ${SMTP_FROM}"
                echo "  Alert Email:        ${ALERT_EMAIL}"
                echo "  TLS Mode:           ${SMTP_TLS}"
                echo "  Auth Method:        ${SMTP_AUTH}"
            else
                echo "  Status:             Disabled"
            fi
            echo ""
            
            # SSL/TLS Configuration
            echo -e "${COLOR_CYAN}━━━ SSL/TLS Configuration (Step 4) ━━━${COLOR_NC}"
            echo "  SSL Mode:           ${SSL_MODE}"
            if [[ "${SSL_MODE}" == "letsencrypt" ]]; then
                if [[ -n "${LE_EMAIL}" ]]; then
                    echo "  LE Email:           ${LE_EMAIL}"
                else
                    echo "  LE Email:           (not provided)"
                fi
                echo "  DNS Verified:       ${DNS_VERIFIED}"
                if [[ "${DNS_VERIFIED}" == "false" ]]; then
                    echo -e "  ${COLOR_YELLOW}⚠ WARNING: DNS not verified - certificate issuance may fail${COLOR_NC}"
                fi
            else
                echo "  Certificate:        Self-signed (for testing)"
            fi
            echo ""
            
            # Paths Configuration
            echo -e "${COLOR_CYAN}━━━ System Paths (Step 5) ━━━${COLOR_NC}"
            echo "  Base Directory:     ${BASE_DIR}"
            echo "    ├─ SFTP:          ${SFTP_DIR}"
            echo "    ├─ Git:           ${GIT_DIR}"
            echo "    ├─ Web:           ${NGINX_DIR}"
            echo "    └─ Backups:       ${BACKUP_DIR}"
            echo ""
            echo "  Cache Size:         ${CACHE_SIZE}"
            echo "  Cache Location:     /var/cache/nginx/cdn"
            echo "  Backup Retention:   ${BACKUP_RETENTION_DAYS} days"
            echo ""
            echo "  Default Quota:      ${DEFAULT_QUOTA_MB} MB per tenant"
            echo "  Warning Thresholds: ${QUOTA_WARN_THRESHOLD_1}%, ${QUOTA_WARN_THRESHOLD_2}%, ${QUOTA_WARN_THRESHOLD_3}%"
            echo ""
            echo "  Git Branch:         ${GIT_DEFAULT_BRANCH}"
            echo "  Auto-commit Delay:  ${AUTOCOMMIT_DELAY}s"
            echo ""
            
            # Gitea Configuration
            echo -e "${COLOR_CYAN}━━━ Gitea Configuration (Step 6) ━━━${COLOR_NC}"
            echo "  Admin Username:     ${GITEA_ADMIN_USER}"
            echo "  Admin Email:        ${GITEA_ADMIN_EMAIL}"
            echo "  Admin Password:     [HIDDEN - $(echo -n "${GITEA_ADMIN_PASS}" | wc -c) characters]"
            echo "  Gitea Version:      ${GITEA_VERSION}"
            echo ""
            echo "  Security Tokens:    Generated"
            echo "    ├─ SECRET_KEY:    ${#GITEA_SECRET_KEY} characters"
            echo "    ├─ INTERNAL_TOKEN: ${#GITEA_INTERNAL_TOKEN} characters"
            echo "    └─ JWT_SECRET:    ${#GITEA_JWT_SECRET} characters"
            echo ""
            
            # Computed Values
            echo -e "${COLOR_CYAN}━━━ Computed Values ━━━${COLOR_NC}"
            echo "  Script Directory:   /opt/scripts/cdn"
            echo "  Config Directory:   /etc/cdn"
            echo "  Log Directory:      /var/log/cdn"
            echo "  Nginx Config:       /etc/nginx/sites-available/"
            echo "  Systemd Services:   /etc/systemd/system/"
            echo ""
            
            # URLs Summary
            echo -e "${COLOR_CYAN}━━━ Access URLs ━━━${COLOR_NC}"
            echo "  CDN Content:        https://${CDN_DOMAIN}/<tenant>/<file>"
            echo "  Gitea Portal:       https://${GITEA_DOMAIN}/"
            echo "  SFTP Access:        sftp://cdn_<tenant>@${CDN_DOMAIN}:${SFTP_PORT}"
            echo ""
            
            echo -e "${COLOR_GREEN}╔═══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
            echo -e "${COLOR_GREEN}║                    END OF CONFIGURATION                           ║${COLOR_NC}"
            echo -e "${COLOR_GREEN}╚═══════════════════════════════════════════════════════════════════╝${COLOR_NC}"
            echo ""
        fi
        
        # ============================================================================
        # Action Menu
        # ============================================================================
        
        local action_choice
        action_choice=$(prompt_menu "What would you like to do?" \
            "✓ Confirm and proceed with installation" \
            "📄 Export configuration to file" \
            "📋 View full summary again" \
            "✏️  Edit Step 1 (Domains)" \
            "✏️  Edit Step 2 (SFTP)" \
            "✏️  Edit Step 3 (SMTP)" \
            "✏️  Edit Step 4 (SSL/TLS)" \
            "✏️  Edit Step 5 (Paths)" \
            "✏️  Edit Step 6 (Gitea Admin)" \
            "❌ Cancel setup")
        
        case "${action_choice}" in
            1)
                # Confirm and proceed
                echo ""
                wizard_info_box "⚠ FINAL CONFIRMATION" \
                    "You are about to proceed with CDN system installation using the configuration above.

This will:
• Create system directories and users
• Install and configure all services
• Generate SSL certificates (if Let's Encrypt)
• Configure nginx, Gitea, systemd services
• Set up monitoring and auto-commit

This process cannot be easily undone without running the uninstall script."
                
                echo ""
                
                if prompt_confirm "Are you absolutely sure you want to proceed?" "no"; then
                    log "✓ Configuration confirmed by user"
                    break
                else
                    warn "Installation cancelled"
                    show_full_summary=false
                fi
                ;;
            
            2)
                # Export configuration
                export_configuration
                show_full_summary=false
                ;;
            
            3)
                # View full summary again
                show_full_summary=true
                ;;
            
            4)
                # Edit Step 1
                warn "Returning to Step 1: Domains"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step1-domains.sh"
                step1_domains
                show_full_summary=true
                ;;
            
            5)
                # Edit Step 2
                warn "Returning to Step 2: SFTP"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step2-sftp.sh"
                step2_sftp
                show_full_summary=true
                ;;
            
            6)
                # Edit Step 3
                warn "Returning to Step 3: SMTP"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step3-smtp.sh"
                step3_smtp
                show_full_summary=true
                ;;
            
            7)
                # Edit Step 4
                warn "Returning to Step 4: SSL/TLS"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step4-letsencrypt.sh"
                step4_letsencrypt
                show_full_summary=true
                ;;
            
            8)
                # Edit Step 5
                warn "Returning to Step 5: Paths"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step5-paths.sh"
                step5_paths
                show_full_summary=true
                ;;
            
            9)
                # Edit Step 6
                warn "Returning to Step 6: Gitea Admin"
                echo ""
                read -p "Press ENTER to continue..."
                # shellcheck disable=SC1091
                source "/opt/scripts/cdn/includes/step6-gitea-admin.sh"
                step6_gitea_admin
                show_full_summary=true
                ;;
            
            10)
                # Cancel
                error "Setup cancelled by user"
                
                if prompt_confirm "Delete wizard state (start fresh next time)?" "no"; then
                    wizard_cleanup false
                    log "Wizard state deleted"
                else
                    log "Wizard state preserved at: ${WIZARD_STATE_FILE}"
                    log "Resume with: cdn-initial-setup --resume"
                fi
                
                return 1
                ;;
            
            *)
                error "Invalid selection"
                ;;
        esac
    done
    
    # ============================================================================
    # Generate Final Configuration Files
    # ============================================================================
    
    echo ""
    info "Generating final configuration files..."
    
    # Create main config file
    generate_config_env
    
    # Create secrets file
    generate_secrets_env
    
    # Mark wizard as complete
    wizard_save_state "WIZARD_COMPLETED" "true"
    wizard_save_state "WIZARD_COMPLETED_AT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    wizard_complete_step "step7-summary"
    
    # ============================================================================
    # Final Instructions
    # ============================================================================
    
    clear
    wizard_header "Setup Wizard Complete!" "7"
    
    echo ""
    echo -e "${COLOR_GREEN}╔═══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_GREEN}║                  CONFIGURATION COMPLETE!                          ║${COLOR_NC}"
    echo -e "${COLOR_GREEN}╚═══════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    
    log "✓ Configuration wizard completed successfully"
    log "✓ Configuration files generated:"
    log "    /etc/cdn/config.env"
    log "    /etc/cdn/secrets.env"
    echo ""
    
    wizard_info_box "Next Steps" \
        "The wizard has completed configuration collection.

The installation process will now:
1. Install system dependencies
2. Create directory structure
3. Configure system users and groups
4. Set up Gitea
5. Configure nginx
6. Request SSL certificates
7. Set up monitoring services
8. Initialize system

Estimated time: 5-15 minutes depending on your system."
    
    echo ""
    
    wizard_footer
    
    return 0
}

################################################################################
# Export Configuration Function
################################################################################

export_configuration() {
    echo ""
    info "Export Configuration"
    echo ""
    
    local default_export_file="/tmp/cdn-config-export-$(date +%Y%m%d-%H%M%S).txt"
    local export_file
    
    export_file=$(prompt_input "Export file path" "${default_export_file}" "" "false" "false")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to get export file path"
        return 1
    fi
    
    info "Exporting configuration to: ${export_file}"
    
    cat > "${export_file}" << EOF
################################################################################
# Multi-Tenant CDN System - Configuration Export
# Generated: $(date)
# Wizard Version: ${WIZARD_VERSION}
################################################################################

# Domain Configuration
CDN_DOMAIN=${CDN_DOMAIN}
GITEA_DOMAIN=${GITEA_DOMAIN}

# Network Configuration
SFTP_PORT=${SFTP_PORT}
SSH_PORT=${SSH_PORT}
GITEA_PORT=3000

# SMTP Configuration
SMTP_ENABLED=${SMTP_ENABLED}
SMTP_PROFILE=${SMTP_PROFILE:-}
SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT:-}
SMTP_AUTH=${SMTP_AUTH:-}
SMTP_TLS=${SMTP_TLS:-}
SMTP_USER=${SMTP_USER:-}
SMTP_PASS=[HIDDEN]
SMTP_FROM=${SMTP_FROM:-}
ALERT_EMAIL=${ALERT_EMAIL:-}

# SSL/TLS Configuration
SSL_MODE=${SSL_MODE}
LE_EMAIL=${LE_EMAIL:-}
LE_ENVIRONMENT=production
DNS_VERIFIED=${DNS_VERIFIED:-false}

# Directory Structure
BASE_DIR=${BASE_DIR}
SFTP_DIR=${SFTP_DIR}
GIT_DIR=${GIT_DIR}
NGINX_DIR=${NGINX_DIR}
BACKUP_DIR=${BACKUP_DIR}
LOG_DIR=/var/log/cdn
SCRIPT_DIR=/opt/scripts/cdn

# Cache Configuration
CACHE_DIR=/var/cache/nginx/cdn
CACHE_SIZE=${CACHE_SIZE}
CACHE_INACTIVE=30d

# Quota Configuration
DEFAULT_QUOTA_MB=${DEFAULT_QUOTA_MB}
QUOTA_WARN_THRESHOLD_1=${QUOTA_WARN_THRESHOLD_1}
QUOTA_WARN_THRESHOLD_2=${QUOTA_WARN_THRESHOLD_2}
QUOTA_WARN_THRESHOLD_3=${QUOTA_WARN_THRESHOLD_3}
QUOTA_CHECK_INTERVAL=30
QUOTA_ENFORCEMENT=block

# Git Configuration
GIT_DEFAULT_BRANCH=${GIT_DEFAULT_BRANCH}
AUTOCOMMIT_DELAY=${AUTOCOMMIT_DELAY}
GIT_COMMIT_PREFIX=[AUTO]

# Backup Configuration
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}
BACKUP_COMPRESS=true

# Gitea Configuration
GITEA_VERSION=${GITEA_VERSION}
GITEA_ADMIN_USER=${GITEA_ADMIN_USER}
GITEA_ADMIN_EMAIL=${GITEA_ADMIN_EMAIL}
GITEA_ADMIN_PASS=[HIDDEN]
GITEA_SECRET_KEY=[HIDDEN - ${#GITEA_SECRET_KEY} chars]
GITEA_INTERNAL_TOKEN=[HIDDEN - ${#GITEA_INTERNAL_TOKEN} chars]
GITEA_JWT_SECRET=[HIDDEN - ${#GITEA_JWT_SECRET} chars]

# System Users
CDN_GROUP=cdnusers
GITEA_USER=git
NGINX_USER=www-data

# Wizard Metadata
WIZARD_VERSION=${WIZARD_VERSION}
WIZARD_COMPLETED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

################################################################################
# End of Configuration Export
################################################################################
EOF
    
    chmod 600 "${export_file}"
    
    log "✓ Configuration exported successfully"
    log "  File: ${export_file}"
    log "  Permissions: 600 (read/write owner only)"
    echo ""
    
    wizard_info_box "Export Complete" \
        "Configuration exported to:
${export_file}

⚠ SECURITY WARNING:
This file contains sensitive information (though passwords are hidden).
Store it securely and delete when no longer needed.

To view: cat ${export_file}
To delete: rm ${export_file}"
    
    echo ""
    read -p "Press ENTER to continue..."
    
    return 0
}

################################################################################
# Generate Final Config Files
################################################################################

generate_config_env() {
    local config_content
    
    # Read template and perform substitutions
    config_content=$(cat "${TEMPLATE_DIR}/config.env.template")
    
    # Perform variable substitutions (all non-sensitive config)
    config_content=$(echo "${config_content}" | envsubst)
    
    # Write to temp location (will be moved to /etc/cdn/ during installation)
    echo "${config_content}" > "${WIZARD_STATE_FILE}.config.env"
    chmod 600 "${WIZARD_STATE_FILE}.config.env"
    
    log "Generated: ${WIZARD_STATE_FILE}.config.env"
}

generate_secrets_env() {
    local secrets_file="${WIZARD_SECRETS_FILE}"
    
    cat > "${secrets_file}" << EOF
################################################################################
# Multi-Tenant CDN System - Secrets (DO NOT COMMIT TO VERSION CONTROL)
# Generated: $(date)
################################################################################

# SMTP Credentials
SMTP_PASS=${SMTP_PASS:-}

# Gitea Admin Credentials
GITEA_ADMIN_PASS=${GITEA_ADMIN_PASS}

# Gitea Security Tokens
GITEA_SECRET_KEY=${GITEA_SECRET_KEY}
GITEA_INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}
GITEA_JWT_SECRET=${GITEA_JWT_SECRET}

################################################################################
EOF
    
    chmod 600 "${secrets_file}"
    
    log "Generated: ${secrets_file}"
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
    
    # Mock all previous steps (load from state file)
    # shellcheck disable=SC1090
    source "${WIZARD_STATE_FILE}"
    
    # Run step
    step7_summary
fi
