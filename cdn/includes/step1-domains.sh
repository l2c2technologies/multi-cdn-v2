#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Setup Wizard Step 1
# Step: Domain Configuration
# Location: /opt/scripts/cdn/includes/step1-domains.sh
################################################################################

step1_domains() {
    wizard_header "Domain Configuration" "1"
    
    wizard_info_box "Domain Setup" \
        "The CDN system requires two separate domains:
         
1. CDN Domain - Used for serving content (e.g., cdn.example.com)
2. Gitea Domain - Used for Git repository web interface (e.g., git.example.com)

Both domains must be different and properly configured in DNS."
    
    wizard_example "Domain Names" \
        "cdn.yourdomain.com" \
        "git.yourdomain.com" \
        "assets.company.com" \
        "repos.company.com"
    
    echo ""
    
    # ============================================================================
    # Collect CDN Domain
    # ============================================================================
    
    local cdn_domain=""
    local default_cdn="${CDN_DOMAIN:-cdn.example.com}"
    
    info "Configure CDN Domain"
    echo "This domain will serve your content files."
    echo ""
    
    while true; do
        cdn_domain=$(prompt_input "Enter CDN domain" "${default_cdn}" "validate_domain" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get valid CDN domain"
            if ! prompt_confirm "Try again?"; then
                return 1
            fi
            continue
        fi
        
        # Show preview
        echo ""
        echo -e "${COLOR_GREEN}CDN URLs will look like:${COLOR_NC}"
        echo -e "  https://${cdn_domain}/tenant-name/images/logo.png"
        echo -e "  https://${cdn_domain}/acme-corp/assets/style.css"
        echo ""
        
        if prompt_confirm "Is this correct?"; then
            break
        fi
    done
    
    # ============================================================================
    # Collect Gitea Domain
    # ============================================================================
    
    local gitea_domain=""
    local default_gitea="${GITEA_DOMAIN:-git.example.com}"
    
    echo ""
    info "Configure Gitea Domain"
    echo "This domain will host the Git repository web interface."
    echo ""
    
    while true; do
        gitea_domain=$(prompt_input "Enter Gitea domain" "${default_gitea}" "validate_domain" "false" "false")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to get valid Gitea domain"
            if ! prompt_confirm "Try again?"; then
                return 1
            fi
            continue
        fi
        
        # Ensure domains are different
        if [[ "${cdn_domain}" == "${gitea_domain}" ]]; then
            error "CDN and Gitea domains must be different!"
            warn "CDN domain: ${cdn_domain}"
            warn "Gitea domain: ${gitea_domain}"
            echo ""
            continue
        fi
        
        # Show preview
        echo ""
        echo -e "${COLOR_GREEN}Gitea URLs will look like:${COLOR_NC}"
        echo -e "  https://${gitea_domain}/"
        echo -e "  https://${gitea_domain}/tenant-name"
        echo ""
        
        if prompt_confirm "Is this correct?"; then
            break
        fi
    done
    
    # ============================================================================
    # Final Confirmation
    # ============================================================================
    
    echo ""
    wizard_info_box "Domain Summary" \
        "CDN Domain:   ${cdn_domain}
Gitea Domain: ${gitea_domain}

Content will be served from: https://${cdn_domain}/
Git repositories at:         https://${gitea_domain}/"
    
    if ! prompt_confirm "Confirm these domain settings?"; then
        warn "Domain configuration cancelled"
        if prompt_confirm "Start over?"; then
            return step1_domains  # Recursive call to restart step
        else
            return 1
        fi
    fi
    
    # ============================================================================
    # Save Configuration
    # ============================================================================
    
    wizard_save_state "CDN_DOMAIN" "${cdn_domain}"
    wizard_save_state "GITEA_DOMAIN" "${gitea_domain}"
    
    # Export for use in other steps
    export CDN_DOMAIN="${cdn_domain}"
    export GITEA_DOMAIN="${gitea_domain}"
    
    log "✓ Domain configuration completed"
    log "  CDN Domain: ${cdn_domain}"
    log "  Gitea Domain: ${gitea_domain}"
    
    wizard_complete_step "step1-domains"
    
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
    
    # Run step
    step1_domains
    
    # Show results
    echo ""
    echo "Saved configuration:"
    grep -E "^(CDN_DOMAIN|GITEA_DOMAIN)=" "${WIZARD_STATE_FILE}"
fi
