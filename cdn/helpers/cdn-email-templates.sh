#!/bin/bash
################################################################################
# Multi-Tenant CDN System - Email Template Library
# Version: 2.0.0
# Location: /opt/scripts/cdn/helpers/cdn-email-templates.sh
# Purpose: Centralized email notification system with templating, queueing,
#          and rate limiting
################################################################################

set -euo pipefail

################################################################################
# CONSTANTS
################################################################################

readonly EMAIL_LIB_VERSION="2.0.0"
readonly EMAIL_QUEUE_DIR="/var/cache/cdn/email-queue"
readonly EMAIL_FALLBACK_LOG="/var/log/cdn/email-fallback.log"
readonly EMAIL_RATE_LIMIT_DIR="/var/cache/cdn/email-rate-limits"
readonly EMAIL_QUEUE_RETENTION_HOURS=24

# Severity levels
readonly LEVEL_INFO="INFO"
readonly LEVEL_WARNING="WARNING"
readonly LEVEL_ERROR="ERROR"
readonly LEVEL_CRITICAL="CRITICAL"

################################################################################
# DEPENDENCIES
################################################################################

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/includes/common.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/includes/common.sh"
else
    echo "ERROR: common.sh not found at ${SCRIPT_DIR}/includes/common.sh" >&2
    exit 1
fi

# Load system configuration
if [[ -f "/etc/cdn/config.env" ]]; then
    # shellcheck disable=SC1091
    source "/etc/cdn/config.env"
else
    error "Configuration not found: /etc/cdn/config.env"
    exit 1
fi

################################################################################
# INITIALIZATION
################################################################################

# Create required directories
initialize_email_system() {
    local dirs=(
        "${EMAIL_QUEUE_DIR}"
        "${EMAIL_RATE_LIMIT_DIR}"
        "$(dirname "${EMAIL_FALLBACK_LOG}")"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            chmod 700 "${dir}"
        fi
    done
    
    # Create fallback log if it doesn't exist
    if [[ ! -f "${EMAIL_FALLBACK_LOG}" ]]; then
        touch "${EMAIL_FALLBACK_LOG}"
        chmod 600 "${EMAIL_FALLBACK_LOG}"
    fi
    
    debug "Email system initialized"
}

# Initialize on load
initialize_email_system

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Get severity color for terminal output
get_severity_color() {
    local level="$1"
    
    case "${level}" in
        "${LEVEL_INFO}")
            echo "${COLOR_BLUE}"
            ;;
        "${LEVEL_WARNING}")
            echo "${COLOR_YELLOW}"
            ;;
        "${LEVEL_ERROR}")
            echo "${COLOR_RED}"
            ;;
        "${LEVEL_CRITICAL}")
            echo -e "${COLOR_RED}\033[1m"  # Bold red
            ;;
        *)
            echo "${COLOR_NC}"
            ;;
    esac
}

# Get severity icon
get_severity_icon() {
    local level="$1"
    
    case "${level}" in
        "${LEVEL_INFO}")
            echo "ℹ"
            ;;
        "${LEVEL_WARNING}")
            echo "⚠"
            ;;
        "${LEVEL_ERROR}")
            echo "✖"
            ;;
        "${LEVEL_CRITICAL}")
            echo "🔥"
            ;;
        *)
            echo "•"
            ;;
    esac
}

# Check if SMTP is available
check_smtp_available() {
    # Check if SMTP is enabled
    if [[ "${SMTP_ENABLED:-false}" != "true" ]]; then
        debug "SMTP is disabled in configuration"
        return 1
    fi
    
    # Check if msmtp is installed
    if ! command -v msmtp &> /dev/null; then
        warn "msmtp command not found"
        return 1
    fi
    
    # Check if msmtprc exists
    if [[ ! -f /etc/msmtprc ]]; then
        warn "SMTP configuration not found: /etc/msmtprc"
        return 1
    fi
    
    return 0
}

# Get tenant email from configuration
get_tenant_email() {
    local tenant="$1"
    local config_file="/etc/cdn/tenants/${tenant}.env"
    
    if [[ ! -f "${config_file}" ]]; then
        error "Tenant configuration not found: ${config_file}"
        return 1
    fi
    
    # Source config and extract GIT_USER_EMAIL
    local tenant_email
    tenant_email=$(grep "^GIT_USER_EMAIL=" "${config_file}" | cut -d= -f2- | tr -d '"' | tr -d "'")
    
    if [[ -z "${tenant_email}" ]]; then
        error "GIT_USER_EMAIL not found in tenant config: ${tenant}"
        return 1
    fi
    
    echo "${tenant_email}"
}

# Get all tenant emails
get_all_tenant_emails() {
    local -a emails=()
    
    if [[ ! -d "/etc/cdn/tenants" ]]; then
        warn "Tenant configuration directory not found"
        return 1
    fi
    
    for config_file in /etc/cdn/tenants/*.env; do
        if [[ -f "${config_file}" ]]; then
            local email
            email=$(grep "^GIT_USER_EMAIL=" "${config_file}" | cut -d= -f2- | tr -d '"' | tr -d "'")
            if [[ -n "${email}" ]]; then
                emails+=("${email}")
            fi
        fi
    done
    
    if [[ ${#emails[@]} -eq 0 ]]; then
        warn "No tenant emails found"
        return 1
    fi
    
    printf "%s\n" "${emails[@]}"
}

################################################################################
# RATE LIMITING FUNCTIONS
################################################################################

# Generate rate limit key
generate_rate_limit_key() {
    local recipient="$1"
    local alert_type="$2"
    
    # Create hash of recipient + alert_type
    echo "${recipient}-${alert_type}" | sha256sum | cut -d' ' -f1
}

# Check if alert should be sent (rate limiting)
should_send_alert() {
    local recipient="$1"
    local alert_type="$2"
    local cooldown_seconds="${3:-3600}"  # Default: 1 hour
    
    local rate_key
    rate_key=$(generate_rate_limit_key "${recipient}" "${alert_type}")
    local rate_file="${EMAIL_RATE_LIMIT_DIR}/${rate_key}"
    
    if [[ ! -f "${rate_file}" ]]; then
        # No previous alert, allow
        return 0
    fi
    
    # Check age of rate limit file
    local last_sent
    last_sent=$(stat -c %Y "${rate_file}" 2>/dev/null || echo 0)
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - last_sent))
    
    if [[ ${elapsed} -ge ${cooldown_seconds} ]]; then
        # Cooldown expired, allow
        return 0
    fi
    
    # Still in cooldown
    debug "Rate limit active for ${alert_type} to ${recipient} (${elapsed}s/${cooldown_seconds}s)"
    return 1
}

# Mark alert as sent (update rate limit)
mark_alert_sent() {
    local recipient="$1"
    local alert_type="$2"
    
    local rate_key
    rate_key=$(generate_rate_limit_key "${recipient}" "${alert_type}")
    local rate_file="${EMAIL_RATE_LIMIT_DIR}/${rate_key}"
    
    # Touch file to update timestamp
    touch "${rate_file}"
    
    debug "Rate limit updated for ${alert_type} to ${recipient}"
}

# Clean up old rate limit files
cleanup_rate_limits() {
    local max_age_days="${1:-7}"
    
    if [[ ! -d "${EMAIL_RATE_LIMIT_DIR}" ]]; then
        return 0
    fi
    
    local count=0
    while IFS= read -r -d '' file; do
        rm -f "${file}"
        ((count++))
    done < <(find "${EMAIL_RATE_LIMIT_DIR}" -type f -mtime "+${max_age_days}" -print0)
    
    if [[ ${count} -gt 0 ]]; then
        log "Cleaned up ${count} old rate limit files"
    fi
}

################################################################################
# EMAIL TEMPLATE GENERATOR
################################################################################

# Generate formatted email body
generate_email() {
    local level="$1"
    local subject="$2"
    local tenant="${3:-}"
    shift 3
    
    # Remaining arguments are sections (key-value pairs)
    local -A sections=()
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        sections["${key}"]="${value}"
        shift 2
    done
    
    # Get severity icon
    local icon
    icon=$(get_severity_icon "${level}")
    
    # Build email body
    local email_body=""
    
    # Header
    if [[ -n "${tenant}" ]]; then
        email_body+="Hello ${tenant} team,\n\n"
    else
        email_body+="CDN System Administrator,\n\n"
    fi
    
    email_body+="═══════════════════════════════════════════════════════════════════════════════\n"
    email_body+="${icon} ${level}: ${subject}\n"
    email_body+="═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    # Add sections
    for key in "${!sections[@]}"; do
        email_body+="${key}:\n"
        email_body+="${sections[${key}]}\n\n"
    done
    
    # Footer
    email_body+="═══════════════════════════════════════════════════════════════════════════════\n"
    
    if [[ -n "${tenant}" ]]; then
        email_body+="Tenant: ${tenant}\n"
        email_body+="CDN URL: https://${CDN_DOMAIN}/${tenant}/\n"
        email_body+="Git Portal: https://${GITEA_DOMAIN}/${tenant}\n"
    fi
    
    email_body+="Support Contact: ${ALERT_EMAIL}\n"
    email_body+="Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')\n"
    email_body+="═══════════════════════════════════════════════════════════════════════════════\n\n"
    email_body+="This is an automated message from the Multi-Tenant CDN monitoring system.\n"
    email_body+="Please do not reply directly to this email.\n"
    
    echo -e "${email_body}"
}

################################################################################
# EMAIL QUEUE MANAGEMENT
################################################################################

# Queue email for later delivery
queue_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    local priority="${4:-normal}"  # normal, high
    local cc_recipients="${5:-}"  # Comma-separated CC list
    
    # Generate unique queue ID
    local queue_id
    queue_id="$(date +%s)-$(uuidgen 2>/dev/null || echo $$-${RANDOM})"
    local queue_file="${EMAIL_QUEUE_DIR}/${queue_id}.eml"
    
    # Write email to queue
    cat > "${queue_file}" << EOF
To: ${recipient}
Cc: ${cc_recipients}
Subject: ${subject}
Priority: ${priority}
Queued-At: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Retry-Count: 0

${body}
EOF
    
    chmod 600 "${queue_file}"
    
    log "Email queued: ${queue_id} -> ${recipient}"
    
    # Also log to fallback
    log_to_fallback "${recipient}" "${subject}" "${body}"
}

# Log email to fallback log file
log_to_fallback() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "FALLBACK EMAIL LOG"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Recipient: ${recipient}"
        echo "Subject: ${subject}"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "${body}"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo ""
    } >> "${EMAIL_FALLBACK_LOG}"
}

# Process email queue (retry failed sends)
process_email_queue() {
    if [[ ! -d "${EMAIL_QUEUE_DIR}" ]]; then
        return 0
    fi
    
    local processed=0
    local failed=0
    local expired=0
    
    for queue_file in "${EMAIL_QUEUE_DIR}"/*.eml; do
        if [[ ! -f "${queue_file}" ]]; then
            continue
        fi
        
        # Extract email metadata
        local recipient
        recipient=$(grep "^To:" "${queue_file}" | cut -d' ' -f2-)
        local subject
        subject=$(grep "^Subject:" "${queue_file}" | cut -d' ' -f2-)
        local cc_recipients
        cc_recipients=$(grep "^Cc:" "${queue_file}" | cut -d' ' -f2-)
        local queued_at
        queued_at=$(grep "^Queued-At:" "${queue_file}" | cut -d' ' -f2-)
        local retry_count
        retry_count=$(grep "^Retry-Count:" "${queue_file}" | cut -d' ' -f2-)
        
        # Check if expired (>24 hours old)
        local queue_age
        queue_age=$(( $(date +%s) - $(date -d "${queued_at}" +%s 2>/dev/null || echo 0) ))
        
        if [[ ${queue_age} -gt $((EMAIL_QUEUE_RETENTION_HOURS * 3600)) ]]; then
            warn "Queue entry expired: ${queue_file} (age: ${queue_age}s)"
            rm -f "${queue_file}"
            ((expired++))
            continue
        fi
        
        # Extract body (everything after blank line)
        local body
        body=$(awk '/^$/{flag=1; next} flag' "${queue_file}")
        
        # Retry sending
        if send_email_direct "${recipient}" "${subject}" "${body}" "normal" "${cc_recipients}"; then
            log "Successfully sent queued email to ${recipient}"
            rm -f "${queue_file}"
            ((processed++))
        else
            # Increment retry count
            ((retry_count++))
            sed -i "s/^Retry-Count: .*/Retry-Count: ${retry_count}/" "${queue_file}"
            ((failed++))
        fi
    done
    
    if [[ ${processed} -gt 0 ]] || [[ ${failed} -gt 0 ]] || [[ ${expired} -gt 0 ]]; then
        log "Email queue processed: ${processed} sent, ${failed} failed, ${expired} expired"
    fi
}

# Clean up old queue files
cleanup_email_queue() {
    local max_age_hours="${1:-${EMAIL_QUEUE_RETENTION_HOURS}}"
    
    if [[ ! -d "${EMAIL_QUEUE_DIR}" ]]; then
        return 0
    fi
    
    local count=0
    while IFS= read -r -d '' file; do
        rm -f "${file}"
        ((count++))
    done < <(find "${EMAIL_QUEUE_DIR}" -name "*.eml" -type f -mmin "+$((max_age_hours * 60))" -print0)
    
    if [[ ${count} -gt 0 ]]; then
        log "Cleaned up ${count} expired queue files"
    fi
}

################################################################################
# EMAIL SENDING FUNCTIONS
################################################################################

# Send email directly via SMTP
send_email_direct() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    local priority="${4:-normal}"
    local cc_recipients="${5:-}"  # NEW: Comma-separated CC list
    
    if ! check_smtp_available; then
        debug "SMTP not available, cannot send email"
        return 1
    fi
    
    # Validate email address
    if ! validate_email "${recipient}"; then
        error "Invalid email address: ${recipient}"
        return 1
    fi
    
    # Build email headers
    local email_headers="To: ${recipient}
From: ${SMTP_FROM}
Subject: ${subject}
Content-Type: text/plain; charset=UTF-8"
    
    # Add CC header if provided
    if [[ -n "${cc_recipients}" ]]; then
        email_headers="${email_headers}
Cc: ${cc_recipients}"
    fi
    
    # Add priority header if high
    if [[ "${priority}" == "high" ]]; then
        email_headers="${email_headers}
X-Priority: 1
Importance: high"
    fi
    
    # Send via msmtp (will deliver to To + Cc automatically)
    local msmtp_recipients="${recipient}"
    if [[ -n "${cc_recipients}" ]]; then
        # Convert comma-separated CC list to space-separated for msmtp
        msmtp_recipients="${recipient} ${cc_recipients//,/ }"
    fi
    
    if echo -e "${email_headers}\n\n${body}" | msmtp -a default ${msmtp_recipients} 2>&1 | tee -a /var/log/msmtp.log; then
        if [[ -n "${cc_recipients}" ]]; then
            debug "Email sent successfully to ${recipient} (CC: ${cc_recipients})"
        else
            debug "Email sent successfully to ${recipient}"
        fi
        return 0
    else
        warn "Failed to send email to ${recipient}"
        return 1
    fi
}

# Send email to tenant (with queueing and rate limiting)
send_tenant_email() {
    local tenant="$1"
    local subject="$2"
    local body="$3"
    local level="${4:-${LEVEL_INFO}}"
    local alert_type="${5:-general}"
    local cooldown="${6:-3600}"  # Default 1 hour
    
    # Get tenant email
    local tenant_email
    if ! tenant_email=$(get_tenant_email "${tenant}"); then
        error "Cannot send email: tenant email not found for ${tenant}"
        return 1
    fi
    
    # Check rate limit for tenant
    if ! should_send_alert "${tenant_email}" "${alert_type}" "${cooldown}"; then
        debug "Skipping email to ${tenant} due to rate limit"
        return 0
    fi
    
    # Format subject with level
    local formatted_subject="[CDN ${level}] ${subject} - Tenant: ${tenant}"
    
    # Send to tenant with admin CCed (single email, not two separate emails)
    if [[ -z "${ALERT_EMAIL}" ]]; then
        warn "ALERT_EMAIL not configured, sending to tenant only"
        if send_email_direct "${tenant_email}" "${formatted_subject}" "${body}" "normal"; then
            mark_alert_sent "${tenant_email}" "${alert_type}"
            log "Sent ${level} email to tenant ${tenant} (${tenant_email})"
        else
            queue_email "${tenant_email}" "${formatted_subject}" "${body}" "normal"
            log "Queued ${level} email for tenant ${tenant} (${tenant_email})"
        fi
    else
        # Send to tenant with admin CCed
        if send_email_direct "${tenant_email}" "${formatted_subject}" "${body}" "normal" "${ALERT_EMAIL}"; then
            mark_alert_sent "${tenant_email}" "${alert_type}"
            log "Sent ${level} email to tenant ${tenant} (${tenant_email}) with CC to admin (${ALERT_EMAIL})"
        else
            queue_email "${tenant_email}" "${formatted_subject}" "${body}" "normal"
            log "Queued ${level} email for tenant ${tenant} (${tenant_email})"
        fi
    fi
    
    return 0
}

# Send email to admin only
send_admin_email() {
    local subject="$1"
    local body="$2"
    local level="${3:-${LEVEL_INFO}}"
    local alert_type="${4:-general}"
    local cooldown="${5:-3600}"
    
    if [[ -z "${ALERT_EMAIL}" ]]; then
        warn "ALERT_EMAIL not configured, cannot send admin email"
        return 1
    fi
    
    # Check rate limit
    if ! should_send_alert "${ALERT_EMAIL}" "${alert_type}" "${cooldown}"; then
        debug "Skipping admin email due to rate limit"
        return 0
    fi
    
    # Format subject
    local formatted_subject="[CDN ${level}] ${subject}"
    
    # Send
    if send_email_direct "${ALERT_EMAIL}" "${formatted_subject}" "${body}" "high"; then
        mark_alert_sent "${ALERT_EMAIL}" "${alert_type}"
        log "Sent ${level} email to admin (${ALERT_EMAIL})"
        return 0
    else
        queue_email "${ALERT_EMAIL}" "${formatted_subject}" "${body}" "high"
        log "Queued ${level} email for admin (${ALERT_EMAIL})"
        return 0
    fi
}

# Broadcast email to all tenants and admin
send_broadcast_email() {
    local subject="$1"
    local body="$2"
    local level="${3:-${LEVEL_WARNING}}"
    local alert_type="${4:-broadcast}"
    
    # Format subject
    local formatted_subject="[CDN ${level}] SYSTEM NOTICE: ${subject}"
    
    # Get all tenant emails
    local -a tenant_emails
    if ! mapfile -t tenant_emails < <(get_all_tenant_emails); then
        warn "Cannot broadcast: no tenant emails found"
    else
        log "Broadcasting to ${#tenant_emails[@]} tenants..."
        
        for tenant_email in "${tenant_emails[@]}"; do
            # Check rate limit per tenant
            if should_send_alert "${tenant_email}" "${alert_type}" 3600; then
                if send_email_direct "${tenant_email}" "${formatted_subject}" "${body}" "high"; then
                    mark_alert_sent "${tenant_email}" "${alert_type}"
                else
                    queue_email "${tenant_email}" "${formatted_subject}" "${body}" "high"
                fi
            fi
        done
    fi
    
    # Always send to admin
    if [[ -n "${ALERT_EMAIL}" ]]; then
        send_admin_email "${subject}" "${body}" "${level}" "${alert_type}"
    fi
    
    log "Broadcast email sent/queued for ${#tenant_emails[@]} tenants + admin"
}

################################################################################
# COMMAND LINE INTERFACE
################################################################################

# Show usage information
show_usage() {
    cat << EOF
Multi-Tenant CDN Email Template Library v${EMAIL_LIB_VERSION}

Usage: $(basename "$0") <command> [arguments]

Commands:
  process-queue              Process queued emails (retry failed sends)
  cleanup-queue [hours]      Clean up queue files older than N hours (default: 24)
  cleanup-limits [days]      Clean up rate limit files older than N days (default: 7)
  test-smtp                  Test SMTP connectivity
  test-tenant <tenant>       Send test email to tenant
  test-admin                 Send test email to admin
  test-broadcast             Send test broadcast to all tenants + admin
  help                       Show this help message

Examples:
  # Process email queue (run from cron every 5 minutes)
  $(basename "$0") process-queue

  # Clean up old files
  $(basename "$0") cleanup-queue 48
  $(basename "$0") cleanup-limits 14

  # Test emails
  $(basename "$0") test-smtp
  $(basename "$0") test-tenant example-tenant
  $(basename "$0") test-admin

Functions (when sourced):
  generate_email <level> <subject> <tenant> <key> <value> ...
  send_tenant_email <tenant> <subject> <body> [level] [alert_type] [cooldown]
  send_admin_email <subject> <body> [level] [alert_type] [cooldown]
  send_broadcast_email <subject> <body> [level] [alert_type]
  get_tenant_email <tenant>
  should_send_alert <recipient> <alert_type> [cooldown]
  mark_alert_sent <recipient> <alert_type>

EOF
}

# Test SMTP connectivity
test_smtp() {
    echo "Testing SMTP connectivity..."
    echo ""
    
    if ! check_smtp_available; then
        error "SMTP is not available"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check SMTP_ENABLED in /etc/cdn/config.env"
        echo "  2. Verify msmtp is installed: command -v msmtp"
        echo "  3. Check /etc/msmtprc exists and is configured"
        echo ""
        return 1
    fi
    
    echo "✓ SMTP is enabled"
    echo "✓ msmtp is installed"
    echo "✓ /etc/msmtprc exists"
    echo ""
    echo "SMTP Configuration:"
    echo "  Host: ${SMTP_HOST}"
    echo "  Port: ${SMTP_PORT}"
    echo "  From: ${SMTP_FROM}"
    echo "  User: ${SMTP_USER}"
    echo ""
    
    return 0
}

# Test email to tenant
test_tenant_email() {
    local tenant="$1"
    
    if [[ -z "${tenant}" ]]; then
        error "Tenant name required"
        return 1
    fi
    
    echo "Sending test email to tenant: ${tenant}"
    echo ""
    
    local subject="Test Email"
    local body
    body=$(generate_email \
        "${LEVEL_INFO}" \
        "Email System Test" \
        "${tenant}" \
        "TEST STATUS" "This is a test email from the CDN email system" \
        "PURPOSE" "Verify email delivery is working correctly" \
        "ACTIONS REQUIRED" "No action required. This is only a test.")
    
    if send_tenant_email "${tenant}" "${subject}" "${body}" "${LEVEL_INFO}" "test" 0; then
        echo "✓ Test email sent successfully"
        return 0
    else
        error "Test email failed"
        return 1
    fi
}

# Test email to admin
test_admin_email() {
    echo "Sending test email to admin: ${ALERT_EMAIL}"
    echo ""
    
    local subject="Email System Test"
    local body
    body=$(generate_email \
        "${LEVEL_INFO}" \
        "Email System Test" \
        "" \
        "TEST STATUS" "This is a test email from the CDN email system" \
        "PURPOSE" "Verify admin email delivery is working correctly" \
        "CONFIGURATION" "SMTP Host: ${SMTP_HOST}:${SMTP_PORT}
From: ${SMTP_FROM}
Admin Email: ${ALERT_EMAIL}")
    
    if send_admin_email "${subject}" "${body}" "${LEVEL_INFO}" "test" 0; then
        echo "✓ Test email sent successfully"
        return 0
    else
        error "Test email failed"
        return 1
    fi
}

# Test broadcast email
test_broadcast_email() {
    echo "Sending test broadcast email to all tenants + admin..."
    echo ""
    
    local subject="Email System Test - Broadcast"
    local body
    body=$(generate_email \
        "${LEVEL_INFO}" \
        "Broadcast Email Test" \
        "" \
        "TEST STATUS" "This is a test broadcast from the CDN email system" \
        "RECIPIENTS" "All tenant emails + administrator" \
        "PURPOSE" "Verify broadcast functionality is working correctly")
    
    if send_broadcast_email "${subject}" "${body}" "${LEVEL_INFO}" "test"; then
        echo "✓ Broadcast email sent/queued successfully"
        return 0
    else
        error "Broadcast email failed"
        return 1
    fi
}

################################################################################
# COMMAND DISPATCHER
################################################################################

# Main function for CLI usage
main() {
    local command="${1:-}"
    
    if [[ -z "${command}" ]]; then
        show_usage
        exit 0
    fi
    
    case "${command}" in
        process-queue)
            log "Processing email queue..."
            process_email_queue
            ;;
        
        cleanup-queue)
            local hours="${2:-${EMAIL_QUEUE_RETENTION_HOURS}}"
            log "Cleaning up email queue (older than ${hours} hours)..."
            cleanup_email_queue "${hours}"
            ;;
        
        cleanup-limits)
            local days="${2:-7}"
            log "Cleaning up rate limits (older than ${days} days)..."
            cleanup_rate_limits "${days}"
            ;;
        
        test-smtp)
            test_smtp
            ;;
        
        test-tenant)
            if [[ -z "${2:-}" ]]; then
                error "Tenant name required"
                echo "Usage: $0 test-tenant <tenant-name>"
                exit 1
            fi
            test_tenant_email "$2"
            ;;
        
        test-admin)
            test_admin_email
            ;;
        
        test-broadcast)
            test_broadcast_email
            ;;
        
        help|--help|-h)
            show_usage
            exit 0
            ;;
        
        *)
            error "Unknown command: ${command}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

################################################################################
# EXECUTION
################################################################################

# If script is executed directly (not sourced), run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# If sourced, just make functions available
debug "Email template library v${EMAIL_LIB_VERSION} loaded"

################################################################################
# END OF FILE
################################################################################
