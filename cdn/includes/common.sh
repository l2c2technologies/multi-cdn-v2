#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Common Functions Library
# Version: 2.0.0
# Location: /opt/scripts/cdn/includes/common.sh
# Purpose: Reusable functions for logging, validation, configuration management
################################################################################

# Strict error handling
set -eE

################################################################################
# CONSTANTS
################################################################################

readonly COMMON_LIB_VERSION="2.0.0"
readonly CONFIG_DIR="/etc/cdn"
readonly CONFIG_FILE="${CONFIG_DIR}/config.env"
readonly KEYS_DIR="${CONFIG_DIR}/keys"
readonly TEMPLATE_DIR="/opt/scripts/cdn/templates"
readonly LOG_DIR="/var/log/cdn"

# Color codes for terminal output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m' # No Color

# Email notification flag (set by load_configuration)
SMTP_ENABLED="${SMTP_ENABLED:-false}"
SMTP_FROM="${SMTP_FROM:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Internal helper for timestamp
_get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Internal helper for email alerts
_send_email_alert() {
    local subject="$1"
    local body="$2"
    local priority="${3:-normal}"
    
    # Only send if SMTP is enabled and configured
    if [[ "${SMTP_ENABLED}" != "true" ]] || [[ -z "${ALERT_EMAIL}" ]]; then
        return 0
    fi
    
    # Check if msmtp is available
    if ! command -v msmtp &> /dev/null; then
        return 0
    fi
    
    # Construct email with priority header
    local priority_header=""
    case "${priority}" in
        high|critical)
            priority_header="X-Priority: 1\nImportance: high"
            ;;
        normal)
            priority_header="X-Priority: 3\nImportance: normal"
            ;;
        low)
            priority_header="X-Priority: 5\nImportance: low"
            ;;
    esac
    
    # Send email (non-blocking, ignore errors)
    {
        echo -e "To: ${ALERT_EMAIL}"
        echo -e "From: ${SMTP_FROM}"
        echo -e "Subject: ${subject}"
        echo -e "${priority_header}"
        echo -e "Content-Type: text/plain; charset=UTF-8"
        echo -e ""
        echo -e "${body}"
    } | msmtp -a default "${ALERT_EMAIL}" &> /dev/null &
    
    return 0
}

# Log info messages (green)
log() {
    local message="$*"
    local timestamp
    timestamp="$(_get_timestamp)"
    
    echo -e "${COLOR_GREEN}[INFO]${COLOR_NC} [${timestamp}] ${message}" >&2
    
    # Also log to syslog if available
    if command -v logger &> /dev/null; then
        logger -t "cdn-system" -p user.info "${message}"
    fi
}

# Log setup/info messages (blue)
info() {
    local message="$*"
    local timestamp
    timestamp="$(_get_timestamp)"
    
    echo -e "${COLOR_BLUE}[SETUP]${COLOR_NC} [${timestamp}] ${message}" >&2
    
    if command -v logger &> /dev/null; then
        logger -t "cdn-system" -p user.info "${message}"
    fi
}

# Log warning messages (yellow) with optional email alert
warn() {
    local message="$*"
    local timestamp
    local hostname
    timestamp="$(_get_timestamp)"
    hostname="$(hostname -f 2>/dev/null || hostname)"
    
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} [${timestamp}] ${message}" >&2
    
    if command -v logger &> /dev/null; then
        logger -t "cdn-system" -p user.warning "${message}"
    fi
    
    # Send email alert for warnings
    _send_email_alert \
        "[CDN Warning] ${hostname}: ${message:0:100}" \
        "Warning occurred at ${timestamp} on ${hostname}\n\nDetails:\n${message}" \
        "normal"
}

# Log error messages (red) to stderr with email alert
error() {
    local message="$*"
    local timestamp
    local hostname
    local caller_info
    timestamp="$(_get_timestamp)"
    hostname="$(hostname -f 2>/dev/null || hostname)"
    
    # Get caller information for debugging
    if [[ "${BASH_SOURCE[1]:-}" != "" ]]; then
        caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}"
    else
        caller_info="unknown"
    fi
    
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} [${timestamp}] ${message}" >&2
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} [${timestamp}] Called from: ${caller_info}" >&2
    
    if command -v logger &> /dev/null; then
        logger -t "cdn-system" -p user.err "${message} (from ${caller_info})"
    fi
    
    # Send critical email alert for errors
    _send_email_alert \
        "[CDN ERROR] ${hostname}: ${message:0:100}" \
        "ERROR occurred at ${timestamp} on ${hostname}\n\nDetails:\n${message}\n\nCalled from: ${caller_info}" \
        "high"
}

# Log debug messages (cyan) - only if DEBUG is set
debug() {
    if [[ "${DEBUG:-false}" == "true" ]] || [[ "${VERBOSE_LOGGING:-false}" == "true" ]]; then
        local message="$*"
        local timestamp
        timestamp="$(_get_timestamp)"
        
        echo -e "${COLOR_CYAN}[DEBUG]${COLOR_NC} [${timestamp}] ${message}" >&2
        
        if command -v logger &> /dev/null; then
            logger -t "cdn-system" -p user.debug "${message}"
        fi
    fi
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

# Validate domain name (RFC-compliant with DNS verification)
validate_domain() {
    local domain="$1"
    
    if [[ -z "${domain}" ]]; then
        error "Domain name cannot be empty"
        return 1
    fi
    
    # Basic RFC 1035/1123 validation
    # - Total length: 1-253 characters
    # - Labels: 1-63 characters each
    # - Characters: a-z, 0-9, hyphen (not at start/end of label)
    # - Must contain at least one dot (except localhost)
    
    # Check total length
    if [[ ${#domain} -gt 253 ]]; then
        error "Domain name too long (max 253 characters): ${domain}"
        return 1
    fi
    
    # Check for valid characters and structure
    if ! echo "${domain}" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        # Special case: localhost and simple hostnames (for development)
        if [[ "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]]; then
            warn "Simple hostname detected (no TLD): ${domain}"
        else
            error "Invalid domain name format: ${domain}"
            return 1
        fi
    fi
    
    # Check for wildcard domains
    if [[ "${domain}" == *.* ]]; then
        # Wildcard domains are valid for some use cases (e.g., SSL certificates)
        debug "Wildcard domain detected: ${domain}"
    fi
    
    # Verify DNS resolution (if host or dig is available)
    if command -v host &> /dev/null; then
        if ! host "${domain}" &> /dev/null; then
            warn "Domain does not resolve in DNS: ${domain}"
            # Don't fail, just warn - domain might not be set up yet
        else
            debug "Domain DNS validation passed: ${domain}"
        fi
    elif command -v dig &> /dev/null; then
        if ! dig +short "${domain}" &> /dev/null; then
            warn "Domain does not resolve in DNS: ${domain}"
        else
            debug "Domain DNS validation passed: ${domain}"
        fi
    else
        debug "DNS validation tools not available, skipping DNS check"
    fi
    
    return 0
}

# Validate email address format
validate_email() {
    local email="$1"
    
    if [[ -z "${email}" ]]; then
        error "Email address cannot be empty"
        return 1
    fi
    
    # RFC 5322 compliant email validation (simplified but robust)
    # Format: local-part@domain
    # Local part: alphanumeric, dots, hyphens, underscores, plus
    # Domain: standard domain name validation
    
    if ! echo "${email}" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        error "Invalid email address format: ${email}"
        return 1
    fi
    
    # Extract and validate domain part
    local domain="${email##*@}"
    if ! validate_domain "${domain}"; then
        error "Invalid domain in email address: ${email}"
        return 1
    fi
    
    debug "Email validation passed: ${email}"
    return 0
}

# Validate port number (1-65535)
validate_port() {
    local port="$1"
    
    if [[ -z "${port}" ]]; then
        error "Port number cannot be empty"
        return 1
    fi
    
    # Check if it's a valid integer
    if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        error "Port must be a positive integer: ${port}"
        return 1
    fi
    
    # Check range (1-65535)
    if [[ ${port} -lt 1 ]] || [[ ${port} -gt 65535 ]]; then
        error "Port must be between 1 and 65535: ${port}"
        return 1
    fi
    
    # Warn about privileged ports (1-1024) if not root
    if [[ ${port} -lt 1024 ]] && [[ ${EUID} -ne 0 ]]; then
        warn "Port ${port} is privileged (requires root)"
    fi
    
    debug "Port validation passed: ${port}"
    return 0
}

# Validate positive integer
validate_positive_integer() {
    local value="$1"
    local name="${2:-value}"
    
    if [[ -z "${value}" ]]; then
        error "${name} cannot be empty"
        return 1
    fi
    
    if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
        error "${name} must be a positive integer: ${value}"
        return 1
    fi
    
    if [[ ${value} -lt 1 ]]; then
        error "${name} must be greater than zero: ${value}"
        return 1
    fi
    
    debug "Positive integer validation passed: ${name}=${value}"
    return 0
}

################################################################################
# CONFIGURATION MANAGEMENT
################################################################################

# Load configuration from /etc/cdn/config.env
load_configuration() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        warn "Configuration file not found: ${CONFIG_FILE}"
        return 1
    fi
    
    # Source the configuration file
    # shellcheck disable=SC1090
    if ! source "${CONFIG_FILE}"; then
        error "Failed to load configuration file: ${CONFIG_FILE}"
        return 1
    fi
    
    # Verify critical variables
    if [[ "${CONFIG_LOADED:-false}" != "true" ]]; then
        error "Configuration file loaded but CONFIG_LOADED flag not set"
        return 1
    fi
    
    debug "Configuration loaded successfully from ${CONFIG_FILE}"
    return 0
}

# Process template file with variable substitution
process_template() {
    local template_file="$1"
    local output_file="$2"
    
    if [[ -z "${template_file}" ]] || [[ -z "${output_file}" ]]; then
        error "process_template requires template_file and output_file parameters"
        return 1
    fi
    
    if [[ ! -f "${template_file}" ]]; then
        error "Template file not found: ${template_file}"
        return 1
    fi
    
    # Check if envsubst is available
    if ! command -v envsubst &> /dev/null; then
        error "envsubst command not found (install gettext-base package)"
        return 1
    fi
    
    debug "Processing template: ${template_file} -> ${output_file}"
    
    # Create output directory if it doesn't exist
    local output_dir
    output_dir="$(dirname "${output_file}")"
    if [[ ! -d "${output_dir}" ]]; then
        if ! mkdir -p "${output_dir}"; then
            error "Failed to create output directory: ${output_dir}"
            return 1
        fi
    fi
    
    # Process template with variable substitution
    if ! envsubst < "${template_file}" > "${output_file}"; then
        error "Failed to process template: ${template_file}"
        return 1
    fi
    
    # Verify no unsubstituted variables remain (except in comments)
    local unsubstituted
    unsubstituted=$(grep -v '^[[:space:]]*#' "${output_file}" | grep -o '\${[^}]*}' || true)
    
    if [[ -n "${unsubstituted}" ]]; then
        warn "Unsubstituted variables found in ${output_file}:"
        echo "${unsubstituted}" | sort -u | while read -r var; do
            warn "  ${var}"
        done
    fi
    
    log "Template processed successfully: $(basename "${output_file}")"
    return 0
}

# Save configuration to /etc/cdn/config.env
save_configuration() {
    local config_data="$1"
    
    if [[ -z "${config_data}" ]]; then
        error "Configuration data cannot be empty"
        return 1
    fi
    
    # Create /etc/cdn directory if it doesn't exist
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        info "Creating configuration directory: ${CONFIG_DIR}"
        if ! mkdir -p "${CONFIG_DIR}"; then
            error "Failed to create configuration directory: ${CONFIG_DIR}"
            return 1
        fi
        chmod 700 "${CONFIG_DIR}"
    fi
    
    # Create keys subdirectory
    if [[ ! -d "${KEYS_DIR}" ]]; then
        info "Creating keys directory: ${KEYS_DIR}"
        if ! mkdir -p "${KEYS_DIR}"; then
            error "Failed to create keys directory: ${KEYS_DIR}"
            return 1
        fi
        chmod 700 "${KEYS_DIR}"
    fi
    
    # Backup existing configuration
    if [[ -f "${CONFIG_FILE}" ]]; then
        local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        info "Backing up existing configuration to: ${backup_file}"
        if ! cp "${CONFIG_FILE}" "${backup_file}"; then
            error "Failed to backup existing configuration"
            return 1
        fi
        chmod 600 "${backup_file}"
    fi
    
    # Write new configuration
    info "Writing configuration to: ${CONFIG_FILE}"
    if ! echo "${config_data}" > "${CONFIG_FILE}"; then
        error "Failed to write configuration file"
        return 1
    fi
    
    # Set secure permissions (root read/write only)
    chmod 600 "${CONFIG_FILE}"
    chown root:root "${CONFIG_FILE}"
    
    log "Configuration saved successfully"
    return 0
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Check if port is available (TCP and UDP)
check_port_available() {
    local port="$1"
    local protocol="${2:-tcp}" # tcp, udp, or both
    
    if ! validate_port "${port}"; then
        return 1
    fi
    
    local port_in_use=false
    
    # Check TCP port
    if [[ "${protocol}" == "tcp" ]] || [[ "${protocol}" == "both" ]]; then
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            warn "TCP port ${port} is already in use"
            port_in_use=true
        elif netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            warn "TCP port ${port} is already in use"
            port_in_use=true
        else
            debug "TCP port ${port} is available"
        fi
    fi
    
    # Check UDP port
    if [[ "${protocol}" == "udp" ]] || [[ "${protocol}" == "both" ]]; then
        if ss -uln 2>/dev/null | grep -q ":${port} "; then
            warn "UDP port ${port} is already in use"
            port_in_use=true
        elif netstat -uln 2>/dev/null | grep -q ":${port} "; then
            warn "UDP port ${port} is already in use"
            port_in_use=true
        else
            debug "UDP port ${port} is available"
        fi
    fi
    
    # Check firewall rules (if iptables/ufw is available)
    if command -v ufw &> /dev/null; then
        if ufw status 2>/dev/null | grep -q "${port}"; then
            debug "Port ${port} found in UFW firewall rules"
        fi
    elif command -v iptables &> /dev/null; then
        if iptables -L -n 2>/dev/null | grep -q ":${port}"; then
            debug "Port ${port} found in iptables rules"
        fi
    fi
    
    if [[ "${port_in_use}" == "true" ]]; then
        error "Port ${port} is not available"
        return 1
    fi
    
    log "Port ${port} (${protocol}) is available"
    return 0
}

# Get current SSH port from sshd_config
get_current_ssh_port() {
    local sshd_config="/etc/ssh/sshd_config"
    local default_port=22
    
    if [[ ! -f "${sshd_config}" ]]; then
        warn "sshd_config not found, assuming default port ${default_port}"
        echo "${default_port}"
        return 0
    fi
    
    # Parse sshd_config for Port directive
    # Handle: Port 22, Port 2222, #Port 22 (commented)
    local port
    port=$(grep -E '^\s*Port\s+[0-9]+' "${sshd_config}" | awk '{print $2}' | head -n1)
    
    if [[ -z "${port}" ]]; then
        # Check for commented Port directive
        local commented_port
        commented_port=$(grep -E '^\s*#\s*Port\s+[0-9]+' "${sshd_config}" | sed 's/#//' | awk '{print $2}' | head -n1)
        
        if [[ -n "${commented_port}" ]]; then
            debug "Found commented Port directive: ${commented_port}, using default: ${default_port}"
        else
            debug "No Port directive found in sshd_config, using default: ${default_port}"
        fi
        
        port="${default_port}"
    fi
    
    # Handle Include directives (recursive parsing)
    local include_files
    include_files=$(grep -E '^\s*Include\s+' "${sshd_config}" | awk '{print $2}')
    
    if [[ -n "${include_files}" ]]; then
        debug "sshd_config contains Include directives"
        while IFS= read -r include_pattern; do
            # Expand glob pattern
            for include_file in ${include_pattern}; do
                if [[ -f "${include_file}" ]]; then
                    local included_port
                    included_port=$(grep -E '^\s*Port\s+[0-9]+' "${include_file}" | awk '{print $2}' | head -n1)
                    if [[ -n "${included_port}" ]]; then
                        debug "Found Port directive in included file ${include_file}: ${included_port}"
                        port="${included_port}"
                        break 2
                    fi
                fi
            done
        done <<< "${include_files}"
    fi
    
    # Validate port
    if ! validate_port "${port}" 2>/dev/null; then
        warn "Invalid SSH port detected: ${port}, using default: ${default_port}"
        port="${default_port}"
    fi
    
    debug "Current SSH port: ${port}"
    echo "${port}"
    return 0
}

# Ensure script is run as root
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    local cmd="$1"
    command -v "${cmd}" &> /dev/null
}

# Check required commands
check_required_commands() {
    local -a commands=("$@")
    local missing=false
    
    for cmd in "${commands[@]}"; do
        if ! command_exists "${cmd}"; then
            error "Required command not found: ${cmd}"
            missing=true
        fi
    done
    
    if [[ "${missing}" == "true" ]]; then
        error "Please install missing dependencies"
        return 1
    fi
    
    return 0
}

# Generate secure random string
generate_random_string() {
    local length="${1:-32}"
    
    if ! validate_positive_integer "${length}" "length"; then
        return 1
    fi
    
    # Use multiple methods for randomness
    if command_exists openssl; then
        openssl rand -base64 "${length}" | tr -d '/+=' | head -c "${length}"
    elif [[ -r /dev/urandom ]]; then
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${length}"
    else
        error "No secure random source available"
        return 1
    fi
    
    echo
    return 0
}

################################################################################
# INITIALIZATION
################################################################################

# Ensure log directory exists
if [[ ! -d "${LOG_DIR}" ]]; then
    if [[ ${EUID} -eq 0 ]]; then
        mkdir -p "${LOG_DIR}" 2>/dev/null || true
        chmod 755 "${LOG_DIR}" 2>/dev/null || true
    fi
fi

# Load configuration if available (non-fatal)
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

################################################################################
# LIBRARY LOADED
################################################################################

debug "Common library v${COMMON_LIB_VERSION} loaded"

# Return success
return 0 2>/dev/null || true
