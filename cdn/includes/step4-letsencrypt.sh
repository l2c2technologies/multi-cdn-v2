#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 4
# Step: SSL/TLS Certificate Configuration
# Location: /opt/scripts/cdn/includes/step4-letsencrypt.sh
################################################################################

step4_letsencrypt() {
    wizard_header "SSL/TLS Certificate Configuration" "4"
    
    wizard_info_box "SSL Certificates" \
        "The CDN system requires SSL/TLS certificates for HTTPS:

Option 1: Let's Encrypt (Recommended for production)
  • Free, automated, trusted certificates
  • Requires domains to be publicly accessible
  • Auto-renewal every 90 days

Option 2: Self-Signed Certificates (Development/testing)
  • Works without public DNS
  • Browser warnings (not trusted)
  • Good for testing and staging

Both domains need certificates:
  • ${CDN_DOMAIN}
  • ${GITEA_DOMAIN}"
    
    echo ""
    
    # ============================================================================
    # Select SSL Mode
    # ============================================================================
    
    local ssl_mode=""
    local ssl_choice
    
    ssl_choice=$(prompt_menu "Select SSL certificate type:" \
        "Let's Encrypt (production - requires valid DNS)" \
        "Self-Signed (development/testing)")
    
    case "${ssl_choice}" in
        1)
            ssl_mode="letsencrypt"
            ;;
        2)
            ssl_mode="selfsigned"
            log "Self-signed certificates will be generated during installation"
            
            wizard_save_state "SSL_MODE" "${ssl_mode}"
            wizard_save_state "LE_EMAIL" ""
            wizard_save_state "DNS_VERIFIED" "false"
            
            export SSL_MODE="${ssl_mode}"
            
            log "✓ SSL configuration completed (self-signed)"
            wizard_complete_step "step4-letsencrypt"
            
            wizard_footer
            echo "Press ENTER to continue to next step..."
            read -r
            return 0
            ;;
        *)
            error "Invalid SSL mode selection"
            return 1
            ;;
    esac
    
    # ============================================================================
    # Let's Encrypt Configuration
    # ============================================================================
    
    wizard_info_box "Let's Encrypt Requirements" \
        "To use Let's Encrypt, you must ensure:

1. Domains are publicly accessible via internet
2. DNS A records point to this server's IP
3. Port 80 (HTTP) is open and accessible
4. Port 443 (HTTPS) is open and accessible

Let's Encrypt will verify domain ownership by:
  • Placing a file in /.well-known/acme-challenge/
  • Accessing it via HTTP on port 80

Note: Initial nginx config will NOT have SSL sections - these will be added by certbot during certificate installation."
    
    echo ""
    
    # ============================================================================
    # Let's Encrypt Email (Optional)
    # ============================================================================
    
    local le_email=""
    
    if prompt_confirm "Provide email address for Let's Encrypt account?" "yes"; then
        wizard_info_box "Let's Encrypt Email" \
            "Email is used for:
• Certificate expiration notices
• Important account notifications
• Lost key recovery

Email is optional but recommended for production."
        
        echo ""
        
        while true; do
            local default_email="${LE_EMAIL:-${ALERT_EMAIL}}"
            le_email=$(prompt_input "Let's Encrypt email" "${default_email}" "validate_email" "true" "false")
            
            if [[ $? -eq 0 ]]; then
                if [[ -n "${le_email}" ]]; then
                    log "✓ Let's Encrypt email: ${le_email}"
                else
                    warn "No email provided - certificate registration will be anonymous"
                fi
                break
            fi
            
            warn "Invalid email address"
        done
    else
        warn "No email provided for Let's Encrypt"
        warn "You will not receive expiration notices"
        le_email=""
    fi
    
    # ============================================================================
    # DNS Verification
    # ============================================================================
    
    echo ""
    wizard_info_box "⚠ DNS Configuration Required" \
        "BEFORE proceeding, ensure DNS is configured:

${CDN_DOMAIN} → $(curl -s ifconfig.me 2>/dev/null || echo '<your-server-ip>')
${GITEA_DOMAIN} → $(curl -s ifconfig.me 2>/dev/null || echo '<your-server-ip>')

Configure A records in your DNS provider pointing to this server.
DNS propagation can take 5 minutes to 48 hours."
    
    echo ""
    
    if ! prompt_confirm "Have you configured DNS for both domains?" "no"; then
        warn "DNS not configured yet"
        warn "SSL certificates cannot be issued without proper DNS"
        echo ""
        
        wizard_info_box "Next Steps" \
            "1. Configure DNS A records for both domains
2. Wait for DNS propagation (check with: dig ${CDN_DOMAIN})
3. Re-run this wizard with: cdn-initial-setup --resume
4. Or continue and certificates will fail (can retry later)"
        
        echo ""
        
        if ! prompt_confirm "Continue anyway (certificates will fail)?" "no"; then
            info "Exiting to allow DNS configuration"
            info "Resume with: cdn-initial-setup --resume"
            return 1
        fi
        
        wizard_save_state "DNS_VERIFIED" "false"
    else
        # Verify DNS if user claims it's configured
        echo ""
        info "Verifying DNS configuration..."
        echo ""
        
        local dns_ok=true
        
        # Check CDN domain
        if verify_dns "${CDN_DOMAIN}"; then
            log "✓ ${CDN_DOMAIN} DNS verified"
        else
            warn "✗ ${CDN_DOMAIN} DNS verification failed"
            dns_ok=false
        fi
        
        # Check Gitea domain
        if verify_dns "${GITEA_DOMAIN}"; then
            log "✓ ${GITEA_DOMAIN} DNS verified"
        else
            warn "✗ ${GITEA_DOMAIN} DNS verification failed"
            dns_ok=false
        fi
        
        echo ""
        
        if [[ "${dns_ok}" == "false" ]]; then
            warn "DNS verification failed for one or more domains"
            warn "Let's Encrypt will likely fail to issue certificates"
            echo ""
            
            if ! prompt_confirm "Continue anyway?" "no"; then
                info "Exiting to allow DNS configuration"
                return 1
            fi
            
            wizard_save_state "DNS_VERIFIED" "false"
        else
            log "✓ DNS verification successful"
            wizard_save_state "DNS_VERIFIED" "true"
        fi
    fi
    
    # ============================================================================
    # Port 80 Availability Check
    # ============================================================================
    
    echo ""
    info "Checking port 80 availability..."
    
    if check_port_available "80" "tcp"; then
        log "✓ Port 80 is available"
    else
        warn "Port 80 appears to be in use or blocked"
        warn "Let's Encrypt requires port 80 for HTTP-01 challenge"
        echo ""
        
        wizard_info_box "Port 80 Required" \
            "Let's Encrypt verification requires:
• Port 80 must be accessible from internet
• No other service can use port 80 during verification
• Nginx will temporarily use port 80 for ACME challenge

If port 80 is blocked by firewall, open it:
• UFW: sudo ufw allow 80/tcp
• firewalld: sudo firewall-cmd --add-port=80/tcp --permanent
• iptables: sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT"
        
        echo ""
        
        if ! prompt_confirm "Continue anyway?" "yes"; then
            error "Port 80 must be available for Let's Encrypt"
            return 1
        fi
    fi
    
    # Check port 443
    info "Checking port 443 availability..."
    
    if check_port_available "443" "tcp"; then
        log "✓ Port 443 is available"
    else
        warn "Port 443 appears to be in use"
        echo ""
        
        if ! prompt_confirm "Continue anyway?" "yes"; then
            error "Port 443 should be available for HTTPS"
            return 1
        fi
    fi
    
    # ============================================================================
    # Certbot Installation Check
    # ============================================================================
    
    echo ""
    info "Checking for certbot installation..."
    
    if command_exists certbot; then
        local certbot_version
        certbot_version=$(certbot --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -n1)
        log "✓ certbot ${certbot_version} found"
    else
        warn "certbot not found - will be installed during setup"
        
        wizard_info_box "Certbot Installation" \
            "Certbot will be automatically installed during system setup.

Package: certbot + python3-certbot-nginx
Source: Official distribution repositories

If installation fails, install manually:
• Ubuntu/Debian: sudo apt install certbot python3-certbot-nginx
• RHEL/CentOS: sudo dnf install certbot python3-certbot-nginx"
        
        echo ""
    fi
    
    # ============================================================================
    # Certificate Issuance Strategy
    # ============================================================================
    
    wizard_info_box "Certificate Issuance Process" \
        "During installation, certificates will be obtained as follows:

1. Nginx will be configured WITHOUT SSL sections (HTTP only)
2. certbot will be run with --nginx plugin
3. certbot will:
   • Request certificates for both domains
   • Automatically configure SSL in nginx
   • Set up auto-renewal via systemd timer

4. After certbot completes, additional security headers will be added

This approach ensures certbot doesn't fail due to missing certificates."
    
    # ============================================================================
    # Final Confirmation
    # ============================================================================
    
    echo ""
    if ! prompt_confirm "Proceed with Let's Encrypt configuration?"; then
        warn "SSL configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step4_letsencrypt  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Save Configuration
    # ============================================================================
    
    wizard_save_state "SSL_MODE" "${ssl_mode}"
    wizard_save_state "LE_EMAIL" "${le_email}"
    
    # Export for use in other steps
    export SSL_MODE="${ssl_mode}"
    export LE_EMAIL="${le_email}"
    export LE_ENVIRONMENT="production"
    
    log "✓ SSL/TLS configuration completed"
    log "  Mode: ${ssl_mode}"
    
    if [[ -n "${le_email}" ]]; then
        log "  Email: ${le_email}"
    else
        log "  Email: (not provided)"
    fi
    
    wizard_complete_step "step4-letsencrypt"
    
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
    export ALERT_EMAIL="admin@example.com"
    
    # Run step
    step4_letsencrypt
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^(SSL_MODE|LE_EMAIL|DNS_VERIFIED)=" "${WIZARD_STATE_FILE}"
fi
