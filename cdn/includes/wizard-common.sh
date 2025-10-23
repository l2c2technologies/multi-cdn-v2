#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Wizard Common Functions Library
# Version: 2.0.0
# Location: /opt/scripts/cdn/includes/wizard-common.sh
# Purpose: Wizard-specific functions for interactive setup
################################################################################

# Note: This file is sourced AFTER common.sh and extends its functionality

################################################################################
# WIZARD CONSTANTS
################################################################################

readonly WIZARD_VERSION="2.0.0"
readonly WIZARD_STATE_FILE="/tmp/cdn-wizard-state.env"
readonly WIZARD_SECRETS_FILE="/tmp/cdn-wizard-secrets.env"
readonly WIZARD_LOCK_FILE="/tmp/cdn-wizard.lock"

# Wizard step names
readonly -a WIZARD_STEPS=(
    "step1-domains"
    "step2-sftp"
    "step3-smtp"
    "step4-letsencrypt"
    "step5-paths"
    "step6-gitea-admin"
    "step7-summary"
)

################################################################################
# WIZARD STATE MANAGEMENT
################################################################################

# Initialize wizard state
wizard_init() {
    info "Initializing CDN Setup Wizard v${WIZARD_VERSION}"
    
    # Check for existing wizard lock
    if [[ -f "${WIZARD_LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${WIZARD_LOCK_FILE}" 2>/dev/null)
        
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            error "Another wizard instance is running (PID: ${lock_pid})"
            return 1
        else
            warn "Stale lock file found, removing..."
            rm -f "${WIZARD_LOCK_FILE}"
        fi
    fi
    
    # Create lock file
    echo $$ > "${WIZARD_LOCK_FILE}"
    
    # Initialize state file if it doesn't exist
    if [[ ! -f "${WIZARD_STATE_FILE}" ]]; then
        cat > "${WIZARD_STATE_FILE}" << 'EOF'
################################################################################
# CDN Setup Wizard - State File (Temporary)
# This file tracks wizard progress and collected configuration
################################################################################

# Wizard metadata
WIZARD_STARTED=
WIZARD_CURRENT_STEP=
WIZARD_COMPLETED_STEPS=

# Step 1: Domain Configuration
CDN_DOMAIN=
GITEA_DOMAIN=

# Step 2: SFTP Configuration
SFTP_PORT=
SSH_PORT=

# Step 3: SMTP Configuration
SMTP_ENABLED=
SMTP_PROFILE=
SMTP_HOST=
SMTP_PORT=
SMTP_AUTH=
SMTP_TLS=
SMTP_USER=
SMTP_PASS=
SMTP_FROM=
ALERT_EMAIL=

# Step 4: Let's Encrypt Configuration
SSL_MODE=
LE_EMAIL=
DNS_VERIFIED=

# Step 5: Paths Configuration
BASE_DIR=
CACHE_SIZE=
BACKUP_RETENTION_DAYS=

# Step 6: Gitea Admin Configuration
GITEA_ADMIN_USER=
GITEA_ADMIN_EMAIL=
GITEA_ADMIN_PASS=

# Generated values (computed during wizard)
GITEA_SECRET_KEY=
GITEA_INTERNAL_TOKEN=
GITEA_JWT_SECRET=

EOF
        chmod 600 "${WIZARD_STATE_FILE}"
        info "Created new wizard state file"
    else
        info "Found existing wizard state, loading..."
        # shellcheck disable=SC1090
        source "${WIZARD_STATE_FILE}"
    fi
    
    # Initialize secrets file
    if [[ ! -f "${WIZARD_SECRETS_FILE}" ]]; then
        touch "${WIZARD_SECRETS_FILE}"
        chmod 600 "${WIZARD_SECRETS_FILE}"
    fi
    
    return 0
}

# Save wizard state
wizard_save_state() {
    local var_name="$1"
    local var_value="$2"
    
    if [[ -z "${var_name}" ]]; then
        error "wizard_save_state: variable name is required"
        return 1
    fi
    
    # Update in-memory variable
    export "${var_name}=${var_value}"
    
    # Update state file
    if grep -q "^${var_name}=" "${WIZARD_STATE_FILE}"; then
        # Variable exists, update it
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "${WIZARD_STATE_FILE}"
    else
        # Variable doesn't exist, append it
        echo "${var_name}=${var_value}" >> "${WIZARD_STATE_FILE}"
    fi
    
    debug "Saved state: ${var_name}=${var_value}"
    return 0
}

# Mark step as completed
wizard_complete_step() {
    local step_name="$1"
    
    # Load current completed steps
    local completed="${WIZARD_COMPLETED_STEPS}"
    
    # Add step if not already in list
    if [[ ! "${completed}" =~ ${step_name} ]]; then
        if [[ -z "${completed}" ]]; then
            completed="${step_name}"
        else
            completed="${completed},${step_name}"
        fi
        
        wizard_save_state "WIZARD_COMPLETED_STEPS" "${completed}"
        wizard_save_state "WIZARD_CURRENT_STEP" "${step_name}"
    fi
    
    debug "Completed step: ${step_name}"
    return 0
}

# Check if step was completed
wizard_step_completed() {
    local step_name="$1"
    
    if [[ "${WIZARD_COMPLETED_STEPS}" =~ ${step_name} ]]; then
        return 0
    else
        return 1
    fi
}

# Clean up wizard files
wizard_cleanup() {
    local keep_state="${1:-false}"
    
    if [[ "${keep_state}" == "false" ]]; then
        info "Cleaning up wizard temporary files..."
        rm -f "${WIZARD_STATE_FILE}" "${WIZARD_SECRETS_FILE}"
    fi
    
    # Always remove lock file
    rm -f "${WIZARD_LOCK_FILE}"
    
    return 0
}

################################################################################
# INTERACTIVE PROMPT FUNCTIONS
################################################################################

# Prompt user for input with validation
prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local validation_func="$3"
    local allow_empty="${4:-false}"
    local secure_input="${5:-false}"
    
    local user_input=""
    local attempts=0
    local max_attempts=5
    
    while true; do
        # Display prompt
        if [[ -n "${default_value}" ]]; then
            echo -ne "${COLOR_CYAN}${prompt_text}${COLOR_NC} [${default_value}]: "
        else
            echo -ne "${COLOR_CYAN}${prompt_text}${COLOR_NC}: "
        fi
        
        # Read input (secure or normal)
        if [[ "${secure_input}" == "true" ]]; then
            read -rs user_input
            echo  # Print newline after secure input
        else
            read -r user_input
        fi
        
        # Trim whitespace
        user_input="$(echo "${user_input}" | xargs)"
        
        # Use default if empty
        if [[ -z "${user_input}" ]] && [[ -n "${default_value}" ]]; then
            user_input="${default_value}"
        fi
        
        # Check if empty is allowed
        if [[ -z "${user_input}" ]] && [[ "${allow_empty}" == "false" ]]; then
            warn "Input cannot be empty"
            ((attempts++))
            if [[ ${attempts} -ge ${max_attempts} ]]; then
                error "Maximum attempts reached"
                return 1
            fi
            continue
        fi
        
        # If empty and allowed, return empty
        if [[ -z "${user_input}" ]] && [[ "${allow_empty}" == "true" ]]; then
            echo "${user_input}"
            return 0
        fi
        
        # Validate if function provided
        if [[ -n "${validation_func}" ]]; then
            if ${validation_func} "${user_input}"; then
                echo "${user_input}"
                return 0
            else
                warn "Invalid input, please try again"
                ((attempts++))
                if [[ ${attempts} -ge ${max_attempts} ]]; then
                    error "Maximum attempts reached"
                    return 1
                fi
                continue
            fi
        else
            # No validation, accept input
            echo "${user_input}"
            return 0
        fi
    done
}

# Prompt for yes/no confirmation
prompt_confirm() {
    local prompt_text="$1"
    local default_value="${2:-no}"  # yes or no
    
    local response
    
    while true; do
        if [[ "${default_value}" == "yes" ]]; then
            echo -ne "${COLOR_CYAN}${prompt_text}${COLOR_NC} (yes/no) [yes]: "
        else
            echo -ne "${COLOR_CYAN}${prompt_text}${COLOR_NC} (yes/no) [no]: "
        fi
        
        read -r response
        response="$(echo "${response}" | xargs | tr '[:upper:]' '[:lower:]')"
        
        # Use default if empty
        if [[ -z "${response}" ]]; then
            response="${default_value}"
        fi
        
        case "${response}" in
            yes|y)
                return 0
                ;;
            no|n)
                return 1
                ;;
            *)
                warn "Please answer 'yes' or 'no'"
                continue
                ;;
        esac
    done
}

# Prompt for selection from menu
prompt_menu() {
    local prompt_text="$1"
    shift
    local -a options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        error "prompt_menu: no options provided"
        return 1
    fi
    
    while true; do
        echo ""
        echo -e "${COLOR_CYAN}${prompt_text}${COLOR_NC}"
        echo ""
        
        local i=1
        for option in "${options[@]}"; do
            echo "  ${i}) ${option}"
            ((i++))
        done
        
        echo ""
        echo -ne "${COLOR_CYAN}Select option${COLOR_NC} [1-${#options[@]}]: "
        
        local selection
        read -r selection
        selection="$(echo "${selection}" | xargs)"
        
        # Validate selection
        if [[ "${selection}" =~ ^[0-9]+$ ]] && \
           [[ ${selection} -ge 1 ]] && \
           [[ ${selection} -le ${#options[@]} ]]; then
            echo "${selection}"
            return 0
        else
            warn "Invalid selection, please choose 1-${#options[@]}"
        fi
    done
}

################################################################################
# WIZARD UI FUNCTIONS
################################################################################

# Display wizard header
wizard_header() {
    local step_title="$1"
    local step_num="$2"
    local total_steps="7"
    
    clear
    echo ""
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                   ${COLOR_GREEN}Multi-Tenant CDN System Setup Wizard${COLOR_NC}                   ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}║${COLOR_NC}                              Version ${WIZARD_VERSION}                              ${COLOR_BLUE}║${COLOR_NC}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    
    if [[ -n "${step_title}" ]] && [[ -n "${step_num}" ]]; then
        echo -e "${COLOR_CYAN}Step ${step_num}/${total_steps}:${COLOR_NC} ${step_title}"
        echo -e "${COLOR_BLUE}────────────────────────────────────────────────────────────────────────────${COLOR_NC}"
        echo ""
    fi
}

# Display wizard footer with navigation
wizard_footer() {
    echo ""
    echo -e "${COLOR_BLUE}────────────────────────────────────────────────────────────────────────────${COLOR_NC}"
    echo ""
}

# Display progress bar
wizard_progress() {
    local current_step="$1"
    local total_steps=7
    local progress=$((current_step * 100 / total_steps))
    local bar_width=50
    local filled=$((progress * bar_width / 100))
    local empty=$((bar_width - filled))
    
    echo -ne "${COLOR_CYAN}Progress:${COLOR_NC} ["
    
    # Filled portion
    for ((i=0; i<filled; i++)); do
        echo -ne "█"
    done
    
    # Empty portion
    for ((i=0; i<empty; i++)); do
        echo -ne "░"
    done
    
    echo -e "] ${progress}%"
    echo ""
}

# Display information box
wizard_info_box() {
    local title="$1"
    local message="$2"
    
    echo ""
    echo -e "${COLOR_YELLOW}┌─ ${title} ─────────────────────────────────────────────────────────────────┐${COLOR_NC}"
    
    # Word wrap message to fit box (max 76 chars per line)
    echo "${message}" | fold -s -w 76 | while IFS= read -r line; do
        printf "${COLOR_YELLOW}│${COLOR_NC} %-76s ${COLOR_YELLOW}│${COLOR_NC}\n" "${line}"
    done
    
    echo -e "${COLOR_YELLOW}└────────────────────────────────────────────────────────────────────────────┘${COLOR_NC}"
    echo ""
}

# Display example box
wizard_example() {
    local title="$1"
    shift
    local -a examples=("$@")
    
    echo ""
    echo -e "${COLOR_GREEN}Example ${title}:${COLOR_NC}"
    for example in "${examples[@]}"; do
        echo -e "  ${COLOR_CYAN}•${COLOR_NC} ${example}"
    done
    echo ""
}

################################################################################
# FIREWALL DETECTION FUNCTIONS
################################################################################

# Check for firewall rules on a specific port
check_firewall_rules() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    local firewall_found=false
    local firewall_type=""
    local has_rule=false
    
    # Check UFW
    if command_exists ufw; then
        firewall_found=true
        firewall_type="UFW"
        
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            if ufw status numbered 2>/dev/null | grep -qE "${port}/(tcp|udp|any)"; then
                has_rule=true
                info "UFW: Port ${port} has existing rules"
            else
                warn "UFW: Port ${port} is NOT allowed in firewall"
                echo ""
                echo "To allow this port, run:"
                echo -e "  ${COLOR_CYAN}sudo ufw allow ${port}/${protocol}${COLOR_NC}"
                echo ""
            fi
        fi
    fi
    
    # Check firewalld
    if command_exists firewall-cmd; then
        firewall_found=true
        firewall_type="firewalld"
        
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            if firewall-cmd --list-ports 2>/dev/null | grep -q "${port}"; then
                has_rule=true
                info "firewalld: Port ${port} has existing rules"
            else
                warn "firewalld: Port ${port} is NOT allowed in firewall"
                echo ""
                echo "To allow this port, run:"
                echo -e "  ${COLOR_CYAN}sudo firewall-cmd --permanent --add-port=${port}/${protocol}${COLOR_NC}"
                echo -e "  ${COLOR_CYAN}sudo firewall-cmd --reload${COLOR_NC}"
                echo ""
            fi
        fi
    fi
    
    # Check iptables
    if command_exists iptables && [[ "${firewall_type}" == "" ]]; then
        firewall_found=true
        firewall_type="iptables"
        
        if iptables -L -n 2>/dev/null | grep -qE "dpt:${port}|:${port} "; then
            has_rule=true
            info "iptables: Port ${port} has existing rules"
        else
            warn "iptables: Port ${port} may not be allowed"
            echo ""
            echo "To allow this port, run:"
            echo -e "  ${COLOR_CYAN}sudo iptables -A INPUT -p ${protocol} --dport ${port} -j ACCEPT${COLOR_NC}"
            echo ""
        fi
    fi
    
    # Check nftables
    if command_exists nft && [[ "${firewall_type}" == "" ]]; then
        firewall_found=true
        firewall_type="nftables"
        
        if nft list ruleset 2>/dev/null | grep -qE "dport ${port}"; then
            has_rule=true
            info "nftables: Port ${port} has existing rules"
        else
            warn "nftables: Port ${port} may not be allowed"
            echo ""
            echo "Configure nftables rules as needed for port ${port}"
            echo ""
        fi
    fi
    
    if [[ "${firewall_found}" == false ]]; then
        info "No active firewall detected"
    elif [[ "${has_rule}" == false ]]; then
        warn "Firewall (${firewall_type}) is active but port ${port} may be blocked"
        if ! prompt_confirm "Continue anyway?"; then
            return 1
        fi
    fi
    
    return 0
}

################################################################################
# DNS VERIFICATION FUNCTIONS
################################################################################

# Verify DNS resolution for domain
verify_dns() {
    local domain="$1"
    
    info "Verifying DNS resolution for: ${domain}"
    
    if command_exists dig; then
        local result
        result=$(dig +short "${domain}" 2>/dev/null)
        
        if [[ -n "${result}" ]]; then
            log "✓ DNS resolves to: ${result}"
            return 0
        else
            warn "DNS does not resolve for: ${domain}"
            return 1
        fi
    elif command_exists host; then
        if host "${domain}" &> /dev/null; then
            local result
            result=$(host "${domain}" | grep "has address" | head -n1 | awk '{print $NF}')
            log "✓ DNS resolves to: ${result}"
            return 0
        else
            warn "DNS does not resolve for: ${domain}"
            return 1
        fi
    elif command_exists nslookup; then
        if nslookup "${domain}" &> /dev/null; then
            log "✓ DNS appears to resolve (nslookup)"
            return 0
        else
            warn "DNS does not resolve for: ${domain}"
            return 1
        fi
    else
        warn "No DNS lookup tools available (dig, host, nslookup)"
        return 1
    fi
}

################################################################################
# SMTP PRESET PROFILES
################################################################################

# Get SMTP profile configuration
get_smtp_profile() {
    local profile_name="$1"
    
    case "${profile_name}" in
        gmail)
            echo "SMTP_HOST=smtp.gmail.com"
            echo "SMTP_PORT=587"
            echo "SMTP_AUTH=plain"
            echo "SMTP_TLS=starttls"
            ;;
        office365)
            echo "SMTP_HOST=smtp.office365.com"
            echo "SMTP_PORT=587"
            echo "SMTP_AUTH=login"
            echo "SMTP_TLS=starttls"
            ;;
        sendgrid)
            echo "SMTP_HOST=smtp.sendgrid.net"
            echo "SMTP_PORT=587"
            echo "SMTP_AUTH=plain"
            echo "SMTP_TLS=starttls"
            ;;
        aws-ses)
            echo "SMTP_HOST=email-smtp.us-east-1.amazonaws.com"
            echo "SMTP_PORT=587"
            echo "SMTP_AUTH=plain"
            echo "SMTP_TLS=starttls"
            ;;
        custom)
            echo "CUSTOM"
            ;;
        *)
            error "Unknown SMTP profile: ${profile_name}"
            return 1
            ;;
    esac
    
    return 0
}

################################################################################
# GITEA SECRET GENERATION
################################################################################

# Generate Gitea secrets
generate_gitea_secrets() {
    info "Generating Gitea security tokens..."
    
    local secret_key=""
    local internal_token=""
    local jwt_secret=""
    
    # Try using gitea binary if available
    if command_exists gitea; then
        debug "Using gitea binary to generate secrets"
        
        secret_key=$(gitea generate secret SECRET_KEY 2>/dev/null || true)
        internal_token=$(gitea generate secret INTERNAL_TOKEN 2>/dev/null || true)
        jwt_secret=$(gitea generate secret JWT_SECRET 2>/dev/null || true)
    fi
    
    # Fallback to openssl if gitea not available or failed
    if [[ -z "${secret_key}" ]]; then
        debug "Using openssl to generate secrets"
        secret_key=$(openssl rand -base64 48 | tr -d '\n' | head -c 64)
    fi
    
    if [[ -z "${internal_token}" ]]; then
        internal_token=$(openssl rand -base64 84 | tr -d '\n' | head -c 105)
    fi
    
    if [[ -z "${jwt_secret}" ]]; then
        jwt_secret=$(openssl rand -base64 32 | tr -d '\n' | head -c 43)
    fi
    
    # Validate generated secrets
    if [[ ${#secret_key} -lt 32 ]]; then
        error "Failed to generate valid SECRET_KEY"
        return 1
    fi
    
    if [[ ${#internal_token} -lt 32 ]]; then
        error "Failed to generate valid INTERNAL_TOKEN"
        return 1
    fi
    
    if [[ ${#jwt_secret} -lt 32 ]]; then
        error "Failed to generate valid JWT_SECRET"
        return 1
    fi
    
    # Export to environment
    export GITEA_SECRET_KEY="${secret_key}"
    export GITEA_INTERNAL_TOKEN="${internal_token}"
    export GITEA_JWT_SECRET="${jwt_secret}"
    
    # Save to state
    wizard_save_state "GITEA_SECRET_KEY" "${secret_key}"
    wizard_save_state "GITEA_INTERNAL_TOKEN" "${internal_token}"
    wizard_save_state "GITEA_JWT_SECRET" "${jwt_secret}"
    
    log "✓ Gitea secrets generated successfully"
    return 0
}

################################################################################
# LIBRARY LOADED
################################################################################

debug "Wizard common library v${WIZARD_VERSION} loaded"

return 0 2>/dev/null || true
