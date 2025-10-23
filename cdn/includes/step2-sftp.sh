#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 2
# Step: SFTP/SSH Port Configuration
# Location: /opt/scripts/cdn/includes/step2-sftp.sh
################################################################################

step2_sftp() {
    wizard_header "SFTP Port Configuration" "2"
    
    wizard_info_box "SFTP Port Setup" \
        "The CDN system uses SFTP (SSH File Transfer Protocol) for secure file uploads.

SFTP runs on the same port as SSH. We'll detect your current SSH port and use it for the CDN system.

Note: The CDN uses chroot SFTP, which requires SSH configuration."
    
    echo ""
    
    # ============================================================================
    # Detect Current SSH Port
    # ============================================================================
    
    info "Detecting SSH configuration..."
    
    local current_ssh_port
    current_ssh_port=$(get_current_ssh_port)
    
    if [[ -z "${current_ssh_port}" ]]; then
        error "Failed to detect SSH port"
        current_ssh_port=22
        warn "Assuming default SSH port: 22"
    fi
    
    log "Current SSH port detected: ${current_ssh_port}"
    
    # ============================================================================
    # Check Firewall Rules
    # ============================================================================
    
    echo ""
    info "Checking firewall configuration for port ${current_ssh_port}..."
    echo ""
    
    if ! check_firewall_rules "${current_ssh_port}" "tcp"; then
        warn "Firewall check indicated potential issues"
        
        if ! prompt_confirm "Continue with port ${current_ssh_port} anyway?"; then
            error "SFTP port configuration cancelled"
            return 1
        fi
    fi
    
    # ============================================================================
    # SFTP Port Configuration
    # ============================================================================
    
    echo ""
    local sftp_port=""
    local default_sftp="${SFTP_PORT:-${current_ssh_port}}"
    
    wizard_info_box "SFTP Port" \
        "SFTP will use the same port as SSH: ${current_ssh_port}

If you want to use a different port for SFTP, you'll need to:
1. Configure SSH to listen on multiple ports
2. Update firewall rules accordingly

For most installations, using the existing SSH port is recommended."
    
    echo ""
    
    if prompt_confirm "Use existing SSH port ${current_ssh_port} for SFTP?" "yes"; then
        sftp_port="${current_ssh_port}"
        log "Using SSH port ${current_ssh_port} for SFTP"
    else
        warn "Custom SFTP port configuration requires manual SSH setup"
        echo ""
        echo "To use a different port:"
        echo "1. Edit /etc/ssh/sshd_config"
        echo "2. Add multiple 'Port' directives:"
        echo "   Port ${current_ssh_port}"
        echo "   Port <your-custom-port>"
        echo "3. Restart SSH service"
        echo "4. Configure firewall rules"
        echo ""
        
        while true; do
            sftp_port=$(prompt_input "Enter SFTP port" "${default_sftp}" "validate_port" "false" "false")
            
            if [[ $? -ne 0 ]]; then
                error "Failed to get valid SFTP port"
                if ! prompt_confirm "Try again?"; then
                    return 1
                fi
                continue
            fi
            
            # Check if port is available
            if ! check_port_available "${sftp_port}" "tcp"; then
                warn "Port ${sftp_port} appears to be in use"
                
                if ! prompt_confirm "Use this port anyway?"; then
                    continue
                fi
            fi
            
            # Check firewall for custom port
            echo ""
            info "Checking firewall configuration for port ${sftp_port}..."
            echo ""
            
            if ! check_firewall_rules "${sftp_port}" "tcp"; then
                warn "Firewall check indicated potential issues"
                
                if ! prompt_confirm "Continue with port ${sftp_port} anyway?"; then
                    continue
                fi
            fi
            
            break
        done
        
        # Warn about manual configuration
        echo ""
        wizard_info_box "⚠ IMPORTANT" \
            "You selected port ${sftp_port} which differs from your SSH port ${current_ssh_port}.

You MUST manually configure SSH to listen on port ${sftp_port}:

1. Edit: sudo nano /etc/ssh/sshd_config
2. Add: Port ${sftp_port}
3. Test: sudo sshd -t
4. Apply: sudo systemctl restart sshd
5. Update firewall to allow port ${sftp_port}

If not done, SFTP will NOT work!"
        
        echo ""
        if ! prompt_confirm "Have you configured SSH for port ${sftp_port}?" "no"; then
            warn "SSH not configured yet - remember to do this before tenants can upload files"
            echo ""
            read -p "Press ENTER to continue..."
        fi
    fi
    
    # ============================================================================
    # Connection Information
    # ============================================================================
    
    echo ""
    wizard_info_box "SFTP Connection Details" \
        "Tenants will connect using SFTP clients like:
• FileZilla
• WinSCP
• Cyberduck
• Command line: sftp

Connection details:
• Host: ${CDN_DOMAIN:-<your-cdn-domain>}
• Port: ${sftp_port}
• Protocol: SFTP (SSH File Transfer Protocol)
• Username: cdn_<tenant-name>
• Authentication: SSH key (no passwords)"
    
    # ============================================================================
    # Final Confirmation
    # ============================================================================
    
    echo ""
    if ! prompt_confirm "Confirm SFTP port ${sftp_port}?"; then
        warn "SFTP port configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step2_sftp  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Save Configuration
    # ============================================================================
    
    wizard_save_state "SFTP_PORT" "${sftp_port}"
    wizard_save_state "SSH_PORT" "${current_ssh_port}"
    
    # Export for use in other steps
    export SFTP_PORT="${sftp_port}"
    export SSH_PORT="${current_ssh_port}"
    
    log "✓ SFTP port configuration completed"
    log "  SFTP Port: ${sftp_port}"
    log "  SSH Port: ${current_ssh_port}"
    
    if [[ "${sftp_port}" != "${current_ssh_port}" ]]; then
        warn "⚠ SFTP port (${sftp_port}) differs from SSH port (${current_ssh_port})"
        warn "  Ensure SSH is configured to listen on port ${sftp_port}"
    fi
    
    wizard_complete_step "step2-sftp"
    
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
    
    # Mock domains for testing
    export CDN_DOMAIN="cdn.example.com"
    export GITEA_DOMAIN="git.example.com"
    
    # Run step
    step2_sftp
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^(SFTP_PORT|SSH_PORT)=" "${WIZARD_STATE_FILE}"
fi
