#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 3
# Step: SMTP Email Configuration
# Location: /opt/scripts/cdn/includes/step3-smtp.sh
################################################################################

step3_smtp() {
    wizard_header "SMTP Email Configuration" "3"
    
    wizard_info_box "Email Notifications" \
        "The CDN system can send email notifications for:
• Quota warnings and limit alerts
• Auto-commit activity
• System errors and warnings
• Setup completion confirmation

SMTP configuration is optional but recommended for production deployments."
    
    echo ""
    
    # ============================================================================
    # Enable/Disable SMTP
    # ============================================================================
    
    if ! prompt_confirm "Enable email notifications?" "yes"; then
        warn "Email notifications disabled"
        
        wizard_save_state "SMTP_ENABLED" "false"
        export SMTP_ENABLED="false"
        
        log "✓ SMTP configuration skipped (disabled)"
        wizard_complete_step "step3-smtp"
        
        wizard_footer
        echo "Press ENTER to continue to next step..."
        read -r
        return 0
    fi
    
    # ============================================================================
    # Select SMTP Profile or Custom
    # ============================================================================
    
    echo ""
    local smtp_profile=""
    
    local profile_choice
    profile_choice=$(prompt_menu "Select SMTP provider:" \
        "Gmail (smtp.gmail.com)" \
        "Microsoft 365 (smtp.office365.com)" \
        "SendGrid (smtp.sendgrid.net)" \
        "AWS SES (email-smtp.*.amazonaws.com)" \
        "Custom SMTP server")
    
    case "${profile_choice}" in
        1)
            smtp_profile="gmail"
            wizard_info_box "Gmail Configuration" \
                "To use Gmail SMTP:

1. Enable 2-Factor Authentication on your Google Account
2. Generate an App Password:
   • Visit: https://myaccount.google.com/apppasswords
   • Select 'Mail' and your device
   • Copy the 16-character password

3. Use your Gmail address as username
4. Use the App Password (NOT your regular password)"
            echo ""
            ;;
        2)
            smtp_profile="office365"
            wizard_info_box "Microsoft 365 Configuration" \
                "To use Office365 SMTP:

1. Use your full Office365 email address as username
2. Use your regular Office365 password
3. Ensure SMTP is enabled in your Office365 admin panel

Note: If using Modern Authentication, you may need to enable SMTP AUTH."
            echo ""
            ;;
        3)
            smtp_profile="sendgrid"
            wizard_info_box "SendGrid Configuration" \
                "To use SendGrid SMTP:

1. Create API key at: https://app.sendgrid.com/settings/api_keys
2. Use 'apikey' as the username (literal text)
3. Use your API key as the password
4. Verify your sender email in SendGrid dashboard"
            echo ""
            ;;
        4)
            smtp_profile="aws-ses"
            wizard_info_box "AWS SES Configuration" \
                "To use AWS SES SMTP:

1. Create SMTP credentials in AWS SES console
2. Note your SMTP username and password
3. Verify your sender email/domain in SES
4. Request production access (remove sandbox mode)

Note: Replace 'us-east-1' in hostname with your AWS region."
            echo ""
            
            # Allow region customization
            if prompt_confirm "Use a different AWS region than us-east-1?" "no"; then
                local aws_region
                aws_region=$(prompt_input "Enter AWS region" "us-east-1" "" "false" "false")
                # Will be used when setting SMTP_HOST
                export AWS_SES_REGION="${aws_region}"
            fi
            ;;
        5)
            smtp_profile="custom"
            ;;
        *)
            error "Invalid profile selection"
            return 1
            ;;
    esac
    
    # ============================================================================
    # Load Profile Defaults
    # ============================================================================
    
    local smtp_host=""
    local smtp_port=""
    local smtp_auth=""
    local smtp_tls=""
    
    if [[ "${smtp_profile}" != "custom" ]]; then
        info "Loading ${smtp_profile} profile defaults..."
        
        local profile_config
        profile_config=$(get_smtp_profile "${smtp_profile}")
        
        while IFS= read -r line; do
            eval "local ${line}"
        done <<< "${profile_config}"
        
        # Special handling for AWS SES region
        if [[ "${smtp_profile}" == "aws-ses" ]] && [[ -n "${AWS_SES_REGION}" ]]; then
            SMTP_HOST="email-smtp.${AWS_SES_REGION}.amazonaws.com"
        fi
        
        log "Loaded profile: ${smtp_profile}"
        log "  Host: ${SMTP_HOST}"
        log "  Port: ${SMTP_PORT}"
        log "  Auth: ${SMTP_AUTH}"
        log "  TLS: ${SMTP_TLS}"
    fi
    
    # ============================================================================
    # Collect SMTP Configuration
    # ============================================================================
    
    echo ""
    info "SMTP Server Configuration"
    echo ""
    
    # SMTP Host
    local default_host="${SMTP_HOST:-${smtp_host}}"
    smtp_host=$(prompt_input "SMTP hostname" "${default_host}" "validate_domain" "false" "false")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to get valid SMTP hostname"
        return 1
    fi
    
    # SMTP Port
    local default_port="${SMTP_PORT:-${smtp_port:-587}}"
    
    while true; do
        smtp_port=$(prompt_input "SMTP port" "${default_port}" "validate_port" "false" "false")
        
        if [[ $? -eq 0 ]]; then
            break
        fi
        
        warn "Invalid SMTP port"
    done
    
    # SMTP User
    echo ""
    local smtp_user=""
    local default_user="${SMTP_USER:-}"
    
    smtp_user=$(prompt_input "SMTP username (email)" "${default_user}" "validate_email" "false" "false")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to get valid SMTP username"
        return 1
    fi
    
    # SMTP Password
    echo ""
    local smtp_pass=""
    
    while true; do
        warn "Password will not be displayed while typing"
        smtp_pass=$(prompt_input "SMTP password" "" "" "false" "true")
        
        if [[ -z "${smtp_pass}" ]]; then
            warn "Password cannot be empty"
            continue
        fi
        
        # Confirm password
        local smtp_pass_confirm
        smtp_pass_confirm=$(prompt_input "Confirm password" "" "" "false" "true")
        
        if [[ "${smtp_pass}" == "${smtp_pass_confirm}" ]]; then
            log "✓ Password confirmed"
            break
        else
            error "Passwords do not match, try again"
        fi
    done
    
    # SMTP FROM address
    echo ""
    local smtp_from=""
    local default_from="${SMTP_FROM:-cdn-system@${CDN_DOMAIN}}"
    
    smtp_from=$(prompt_input "FROM email address" "${default_from}" "validate_email" "false" "false")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to get valid FROM address"
        return 1
    fi
    
    # Alert recipient email
    echo ""
    local alert_email=""
    local default_alert="${ALERT_EMAIL:-admin@${CDN_DOMAIN}}"
    
    alert_email=$(prompt_input "Alert recipient email" "${default_alert}" "validate_email" "false" "false")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to get valid alert email"
        return 1
    fi
    
    # TLS/STARTTLS Configuration
    echo ""
    if [[ "${smtp_profile}" == "custom" ]]; then
        info "TLS Configuration"
        echo ""
        
        local tls_choice
        tls_choice=$(prompt_menu "Select TLS mode:" \
            "STARTTLS (port 587 - recommended)" \
            "TLS/SSL (port 465)" \
            "No encryption (NOT recommended)")
        
        case "${tls_choice}" in
            1)
                smtp_tls="starttls"
                smtp_auth="plain"
                ;;
            2)
                smtp_tls="on"
                smtp_auth="plain"
                ;;
            3)
                smtp_tls="off"
                smtp_auth="plain"
                warn "⚠ Unencrypted SMTP is insecure!"
                ;;
        esac
    else
        # Use profile defaults
        smtp_tls="${SMTP_TLS:-${smtp_tls}}"
        smtp_auth="${SMTP_AUTH:-${smtp_auth}}"
    fi
    
    # ============================================================================
    # Configuration Summary
    # ============================================================================
    
    echo ""
    wizard_info_box "SMTP Configuration Summary" \
        "Profile: ${smtp_profile}
Host: ${smtp_host}
Port: ${smtp_port}
User: ${smtp_user}
From: ${smtp_from}
Alert Email: ${alert_email}
TLS Mode: ${smtp_tls}
Auth Method: ${smtp_auth}"
    
    if ! prompt_confirm "Is this configuration correct?"; then
        warn "SMTP configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step3_smtp  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Test SMTP Configuration (Create temporary msmtprc)
    # ============================================================================
    
    echo ""
    if prompt_confirm "Test SMTP configuration now?" "yes"; then
        info "Preparing SMTP test..."
        
        # Create temporary msmtprc for testing
        local temp_msmtprc="/tmp/msmtprc.test.$$"
        
        cat > "${temp_msmtprc}" << EOF
defaults
logfile /var/log/msmtp.log
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
tls_certcheck on
tls_min_version TLSv1.2

account default
host ${smtp_host}
port ${smtp_port}
from ${smtp_from}
user ${smtp_user}
password ${smtp_pass}
auth ${smtp_auth}
tls_starttls $([ "${smtp_tls}" == "starttls" ] && echo "on" || echo "off")
EOF
        
        chmod 600 "${temp_msmtprc}"
        
        log "Testing SMTP configuration..."
        log "Sending test email to: ${alert_email}"
        echo ""
        
        if echo -e "Subject: CDN Setup - SMTP Test\n\nCDN system SMTP configuration test at $(date).\n\nIf you receive this email, SMTP is configured correctly.\n\n---\nCDN Domain: ${CDN_DOMAIN}\nGitea Domain: ${GITEA_DOMAIN}" | \
           msmtp --file="${temp_msmtprc}" "${alert_email}" 2>&1; then
            log "✓ Test email sent successfully!"
            echo ""
            
            local email_received=""
            while true; do
                read -p "Did you receive the test email? (yes/no/retry): " email_received
                email_received="$(echo "${email_received}" | xargs | tr '[:upper:]' '[:lower:]')"
                
                case "${email_received}" in
                    yes|y)
                        log "✓ SMTP test successful!"
                        break
                        ;;
                    no|n)
                        warn "Test email not received"
                        warn "Check spam/junk folder"
                        warn "Check logs: /var/log/msmtp.log"
                        echo ""
                        
                        if prompt_confirm "Continue with this configuration anyway?"; then
                            warn "Proceeding despite failed email test"
                            break
                        else
                            rm -f "${temp_msmtprc}"
                            if prompt_confirm "Re-configure SMTP settings?"; then
                                return step3_smtp
                            else
                                return 1
                            fi
                        fi
                        ;;
                    retry)
                        log "Resending test email..."
                        if echo -e "Subject: CDN Setup - SMTP Test (Retry)\n\nRetrying SMTP test at $(date)." | \
                           msmtp --file="${temp_msmtprc}" "${alert_email}" 2>&1; then
                            log "✓ Test email resent"
                        else
                            error "Failed to resend test email"
                        fi
                        ;;
                    *)
                        warn "Please answer 'yes', 'no', or 'retry'"
                        ;;
                esac
            done
        else
            error "Failed to send test email"
            warn "Check logs: /var/log/msmtp.log"
            echo ""
            
            if prompt_confirm "Continue anyway?"; then
                warn "Proceeding despite failed SMTP test"
            else
                rm -f "${temp_msmtprc}"
                if prompt_confirm "Re-configure SMTP settings?"; then
                    return step3_smtp
                else
                    return 1
                fi
            fi
        fi
        
        # Clean up test file
        rm -f "${temp_msmtprc}"
    fi
    
    # ============================================================================
    # Save Configuration
    # ============================================================================
    
    wizard_save_state "SMTP_ENABLED" "true"
    wizard_save_state "SMTP_PROFILE" "${smtp_profile}"
    wizard_save_state "SMTP_HOST" "${smtp_host}"
    wizard_save_state "SMTP_PORT" "${smtp_port}"
    wizard_save_state "SMTP_AUTH" "${smtp_auth}"
    wizard_save_state "SMTP_TLS" "${smtp_tls}"
    wizard_save_state "SMTP_USER" "${smtp_user}"
    wizard_save_state "SMTP_PASS" "${smtp_pass}"
    wizard_save_state "SMTP_FROM" "${smtp_from}"
    wizard_save_state "ALERT_EMAIL" "${alert_email}"
    
    # Export for use in other steps
    export SMTP_ENABLED="true"
    export SMTP_HOST="${smtp_host}"
    export SMTP_PORT="${smtp_port}"
    export SMTP_USER="${smtp_user}"
    export SMTP_PASS="${smtp_pass}"
    export SMTP_FROM="${smtp_from}"
    export ALERT_EMAIL="${alert_email}"
    export SMTP_AUTH="${smtp_auth}"
    export SMTP_TLS="${smtp_tls}"
    
    log "✓ SMTP configuration completed"
    log "  Profile: ${smtp_profile}"
    log "  Host: ${smtp_host}:${smtp_port}"
    log "  From: ${smtp_from}"
    log "  Alerts: ${alert_email}"
    
    wizard_complete_step "step3-smtp"
    
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
    step3_smtp
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^SMTP_" "${WIZARD_STATE_FILE}"
fi
