#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 6
# Step: Gitea Admin Configuration
# Location: /opt/scripts/cdn/includes/step6-gitea-admin.sh
################################################################################

step6_gitea_admin() {
    wizard_header "Gitea Admin Configuration" "6"
    
    wizard_info_box "Gitea Administration" \
        "Gitea is the Git repository web interface for the CDN system.

An administrator account is required for:
• Managing Git repositories
• Creating tenants via web interface
• System configuration
• User management

The admin account will have full access to all repositories."
    
    echo ""
    
    # ============================================================================
    # Detect Current System User
    # ============================================================================
    
    local current_user=""
    local current_email=""
    
    # Try to detect actual user (not root if using sudo)
    if [[ -n "${SUDO_USER}" ]]; then
        current_user="${SUDO_USER}"
    else
        current_user="${USER}"
    fi
    
    # Try to get git email configuration
    if command_exists git; then
        current_email=$(git config --global user.email 2>/dev/null || true)
    fi
    
    if [[ -n "${current_user}" ]] && [[ "${current_user}" != "root" ]]; then
        info "Detected system user: ${current_user}"
        
        if [[ -n "${current_email}" ]]; then
            info "Detected git email: ${current_email}"
        fi
    fi
    
    # ============================================================================
    # Gitea Admin Username
    # ============================================================================
    
    echo ""
    info "Gitea Admin Username"
    echo ""
    echo "Choose a username for the Gitea administrator account."
    echo ""
    
    wizard_example "Admin Usernames" \
        "cdnadmin (default)" \
        "admin" \
        "${current_user}" \
        "gitadmin"
    
    echo ""
    
    local gitea_admin_user=""
    local default_admin_user="${GITEA_ADMIN_USER:-cdnadmin}"
    
    # Offer to use current system user
    if [[ -n "${current_user}" ]] && [[ "${current_user}" != "root" ]]; then
        if prompt_confirm "Use current system username '${current_user}' for Gitea admin?" "no"; then
            default_admin_user="${current_user}"
        fi
    fi
    
    while true; do
        gitea_admin_user=$(prompt_input "Gitea admin username" "${default_admin_user}" "" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get admin username"
            return 1
        fi
        
        # Validate username format
        # Gitea usernames: alphanumeric, dash, underscore, dot (3-40 chars)
        if [[ ! "${gitea_admin_user}" =~ ^[a-zA-Z0-9._-]{3,40}$ ]]; then
            error "Invalid username format"
            warn "Username must be 3-40 characters: letters, numbers, dash, underscore, dot"
            continue
        fi
        
        # Warn if using 'root' or 'admin'
        if [[ "${gitea_admin_user}" == "root" ]] || [[ "${gitea_admin_user}" == "admin" ]]; then
            warn "Username '${gitea_admin_user}' may be a security target"
            
            if ! prompt_confirm "Use this username anyway?"; then
                continue
            fi
        fi
        
        log "✓ Admin username: ${gitea_admin_user}"
        break
    done
    
    # ============================================================================
    # Gitea Admin Email
    # ============================================================================
    
    echo ""
    info "Gitea Admin Email"
    echo ""
    echo "Email address for the administrator account."
    echo "Used for notifications and account recovery."
    echo ""
    
    local gitea_admin_email=""
    local default_admin_email="${GITEA_ADMIN_EMAIL:-${current_email:-admin@${CDN_DOMAIN}}}"
    
    while true; do
        gitea_admin_email=$(prompt_input "Admin email address" "${default_admin_email}" "validate_email" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get admin email"
            return 1
        fi
        
        log "✓ Admin email: ${gitea_admin_email}"
        break
    done
    
    # ============================================================================
    # Gitea Admin Password
    # ============================================================================
    
    echo ""
    info "Gitea Admin Password"
    echo ""
    
    wizard_info_box "Password Requirements" \
        "Password must meet the following criteria:
• Minimum 8 characters
• At least one uppercase letter (recommended)
• At least one lowercase letter (recommended)
• At least one number (recommended)
• Special characters allowed

⚠ IMPORTANT: Store this password securely!
You'll need it to log into Gitea web interface."
    
    echo ""
    
    local gitea_admin_pass=""
    local password_attempts=0
    local max_attempts=5
    
    while true; do
        if [[ ${password_attempts} -ge ${max_attempts} ]]; then
            error "Maximum password attempts reached"
            return 1
        fi
        
        warn "Password will not be displayed while typing"
        gitea_admin_pass=$(prompt_input "Admin password" "" "" "false" "true")
        
        if [[ -z "${gitea_admin_pass}" ]]; then
            error "Password cannot be empty"
            ((password_attempts++))
            continue
        fi
        
        # Validate password strength
        local pass_length=${#gitea_admin_pass}
        local has_upper=false
        local has_lower=false
        local has_digit=false
        local has_special=false
        
        if [[ ${pass_length} -lt 8 ]]; then
            error "Password must be at least 8 characters"
            ((password_attempts++))
            continue
        fi
        
        # Check password complexity
        [[ "${gitea_admin_pass}" =~ [A-Z] ]] && has_upper=true
        [[ "${gitea_admin_pass}" =~ [a-z] ]] && has_lower=true
        [[ "${gitea_admin_pass}" =~ [0-9] ]] && has_digit=true
        [[ "${gitea_admin_pass}" =~ [^a-zA-Z0-9] ]] && has_special=true
        
        # Calculate password strength score
        local strength_score=0
        [[ "${has_upper}" == true ]] && ((strength_score++))
        [[ "${has_lower}" == true ]] && ((strength_score++))
        [[ "${has_digit}" == true ]] && ((strength_score++))
        [[ "${has_special}" == true ]] && ((strength_score++))
        [[ ${pass_length} -ge 12 ]] && ((strength_score++))
        
        # Display strength
        echo ""
        if [[ ${strength_score} -le 1 ]]; then
            warn "Password strength: WEAK"
            warn "Consider adding: uppercase, lowercase, numbers, special chars"
            
            if ! prompt_confirm "Use this weak password anyway?" "no"; then
                ((password_attempts++))
                continue
            fi
        elif [[ ${strength_score} -le 3 ]]; then
            info "Password strength: MODERATE"
        else
            log "Password strength: STRONG"
        fi
        
        # Confirm password
        echo ""
        local gitea_admin_pass_confirm
        gitea_admin_pass_confirm=$(prompt_input "Confirm password" "" "" "false" "true")
        
        if [[ "${gitea_admin_pass}" != "${gitea_admin_pass_confirm}" ]]; then
            error "Passwords do not match"
            ((password_attempts++))
            continue
        fi
        
        log "✓ Password confirmed"
        break
    done
    
    # ============================================================================
    # Generate Gitea Secrets
    # ============================================================================
    
    echo ""
    info "Generating Gitea security tokens..."
    
    if ! generate_gitea_secrets; then
        error "Failed to generate Gitea secrets"
        return 1
    fi
    
    log "✓ Gitea security tokens generated"
    
    # ============================================================================
    # Gitea Configuration Summary
    # ============================================================================
    
    echo ""
    wizard_info_box "Gitea Admin Summary" \
        "Username: ${gitea_admin_user}
Email: ${gitea_admin_email}
Password: [HIDDEN - stored securely]

Gitea Web Interface:
  URL: https://${GITEA_DOMAIN}/
  Login with username and password above

Security Tokens: Generated
  • SECRET_KEY: ${#GITEA_SECRET_KEY} chars
  • INTERNAL_TOKEN: ${#GITEA_INTERNAL_TOKEN} chars
  • JWT_SECRET: ${#GITEA_JWT_SECRET} chars"
    
    if ! prompt_confirm "Confirm Gitea admin configuration?"; then
        warn "Gitea configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step6_gitea_admin  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Save Configuration (Separate sensitive data)
    # ============================================================================
    
    # Save non-sensitive configuration
    wizard_save_state "GITEA_ADMIN_USER" "${gitea_admin_user}"
    wizard_save_state "GITEA_ADMIN_EMAIL" "${gitea_admin_email}"
    
    # Sensitive configuration is already saved by generate_gitea_secrets()
    # Add password to state (will be moved to secrets file later)
    wizard_save_state "GITEA_ADMIN_PASS" "${gitea_admin_pass}"
    
    # Export for use in other steps
    export GITEA_ADMIN_USER="${gitea_admin_user}"
    export GITEA_ADMIN_EMAIL="${gitea_admin_email}"
    export GITEA_ADMIN_PASS="${gitea_admin_pass}"
    
    # Additional Gitea configuration
    wizard_save_state "GITEA_VERSION" "1.24.6"
    export GITEA_VERSION="1.24.6"
    
    log "✓ Gitea admin configuration completed"
    log "  Username: ${gitea_admin_user}"
    log "  Email: ${gitea_admin_email}"
    log "  Secrets: Generated"
    
    # Important reminder
    echo ""
    wizard_info_box "⚠ IMPORTANT REMINDER" \
        "Save your Gitea admin credentials NOW:

Username: ${gitea_admin_user}
Email: ${gitea_admin_email}
Password: [the password you just entered]

You will need these to access:
  https://${GITEA_DOMAIN}/

Credentials are stored securely in /etc/cdn/secrets.env (after installation)"
    
    echo ""
    read -p "Press ENTER to acknowledge and continue..."
    
    wizard_complete_step "step6-gitea-admin"
    
    wizard_footer
    echo "Press ENTER to continue to final step..."
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
    step6_gitea_admin
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^GITEA_ADMIN" "${WIZARD_STATE_FILE}"
fi
