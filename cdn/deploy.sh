#!/bin/bash
################################################################################
# CDN System Deployment Script
# Purpose: Deploy multi-tenant CDN system to production paths
# Version: 1.0.0
# Location: /opt/scripts/cdn/deploy.sh
################################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Deployment configuration
readonly DEPLOY_TARGET="/opt/scripts/cdn"
readonly BIN_DIR="/usr/local/bin"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_DIR="${DEPLOY_TARGET}.backup.${TIMESTAMP}"
readonly REPORT_FILE="/tmp/cdn-deployment-report-${TIMESTAMP}.txt"
readonly CORRECTION_REPORT="/tmp/cdn-path-corrections-${TIMESTAMP}.txt"
readonly SOURCE_DIR="$(pwd)"

# Track statistics
declare -i FILES_DEPLOYED=0
declare -i FILES_CORRECTED=0
declare -i ERRORS=0

################################################################################
# Logging functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$REPORT_FILE"
    ((ERRORS++))
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

################################################################################
# Pre-flight checks
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_source_directory() {
    log_info "Validating source directory: ${SOURCE_DIR}"
    
    if [[ ! -d "${SOURCE_DIR}" ]]; then
        log_error "Source directory does not exist: ${SOURCE_DIR}"
        exit 1
    fi
    
    # Check for critical main scripts
    local -a required_scripts=(
        "cdn-initial-setup.sh"
        "cdn-tenant-manager.sh"
        "cdn-uninstall.sh"
        "cdn-monitoring-setup.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "${SOURCE_DIR}/${script}" ]]; then
            log_error "Required script missing: ${script}"
            exit 1
        fi
    done
    
    log_success "Source directory validation passed"
}

check_dependencies() {
    log_info "Checking system dependencies..."
    
    local -a required_commands=(
        "bash"
        "sha256sum"
        "chmod"
        "chown"
        "ln"
        "mkdir"
        "cp"
        "mv"
        "sed"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "All dependencies satisfied"
}

validate_bash_syntax() {
    local file="$1"
    
    if bash -n "$file" 2>/dev/null; then
        return 0
    else
        log_error "Syntax validation failed: $file"
        bash -n "$file" 2>&1 | tee -a "$REPORT_FILE"
        return 1
    fi
}

################################################################################
# Backup functions
################################################################################

prompt_for_backup() {
    if [[ -d "${DEPLOY_TARGET}" ]]; then
        echo ""
        log_warning "Existing installation detected at: ${DEPLOY_TARGET}"
        echo ""
        echo "Options:"
        echo "  1) Backup and continue"
        echo "  2) Overwrite without backup"
        echo "  3) Cancel deployment"
        echo ""
        read -rp "Select option [1-3]: " choice
        
        case $choice in
            1)
                create_backup
                ;;
            2)
                log_warning "Proceeding without backup (user choice)"
                ;;
            3)
                log_info "Deployment cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
}

create_backup() {
    log_info "Creating backup: ${BACKUP_DIR}"
    
    if ! mv "${DEPLOY_TARGET}" "${BACKUP_DIR}"; then
        log_error "Failed to create backup"
        exit 1
    fi
    
    log_success "Backup created successfully"
    echo "Backup location: ${BACKUP_DIR}" >> "$REPORT_FILE"
}

################################################################################
# Path correction functions
################################################################################

correct_paths_in_file() {
    local file="$1"
    local temp_file="${file}.tmp"
    local corrections=0
    
    # Skip binary files and templates (they should remain as templates)
    if file "$file" | grep -q "executable"; then
        # Create correction report header for this file
        if [[ $corrections -eq 0 ]]; then
            echo "" >> "$CORRECTION_REPORT"
            echo "File: $file" >> "$CORRECTION_REPORT"
            echo "----------------------------------------" >> "$CORRECTION_REPORT"
        fi
        
        # Pattern 1: /usr/local/bin/cdn-autocommit.sh -> /opt/scripts/cdn/helpers/cdn-autocommit.sh
        if grep -q "/usr/local/bin/cdn-autocommit\.sh" "$file"; then
            sed -i 's|/usr/local/bin/cdn-autocommit\.sh|/opt/scripts/cdn/helpers/cdn-autocommit.sh|g' "$file"
            echo "  ✓ Fixed: /usr/local/bin/cdn-autocommit.sh -> /opt/scripts/cdn/helpers/cdn-autocommit.sh" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
        
        # Pattern 2: /usr/local/bin/cdn-quota-functions.sh -> /opt/scripts/cdn/helpers/cdn-quota-functions.sh
        if grep -q "/usr/local/bin/cdn-quota-functions\.sh" "$file"; then
            sed -i 's|/usr/local/bin/cdn-quota-functions\.sh|/opt/scripts/cdn/helpers/cdn-quota-functions.sh|g' "$file"
            echo "  ✓ Fixed: /usr/local/bin/cdn-quota-functions.sh -> /opt/scripts/cdn/helpers/cdn-quota-functions.sh" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
        
        # Pattern 3: /usr/local/bin/cdn-gitea-functions.sh -> /opt/scripts/cdn/helpers/cdn-gitea-functions.sh
        if grep -q "/usr/local/bin/cdn-gitea-functions\.sh" "$file"; then
            sed -i 's|/usr/local/bin/cdn-gitea-functions\.sh|/opt/scripts/cdn/helpers/cdn-gitea-functions.sh|g' "$file"
            echo "  ✓ Fixed: /usr/local/bin/cdn-gitea-functions.sh -> /opt/scripts/cdn/helpers/cdn-gitea-functions.sh" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
        
        # Pattern 4: /usr/local/bin/cdn-tenant-helpers.sh -> /opt/scripts/cdn/helpers/cdn-tenant-helpers.sh
        if grep -q "/usr/local/bin/cdn-tenant-helpers\.sh" "$file"; then
            sed -i 's|/usr/local/bin/cdn-tenant-helpers\.sh|/opt/scripts/cdn/helpers/cdn-tenant-helpers.sh|g' "$file"
            echo "  ✓ Fixed: /usr/local/bin/cdn-tenant-helpers.sh -> /opt/scripts/cdn/helpers/cdn-tenant-helpers.sh" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
        
        # Pattern 5: /usr/local/bin/cdn-setup-letsencrypt.sh -> /opt/scripts/cdn/helpers/cdn-setup-letsencrypt.sh
        if grep -q "/usr/local/bin/cdn-setup-letsencrypt\.sh" "$file"; then
            sed -i 's|/usr/local/bin/cdn-setup-letsencrypt\.sh|/opt/scripts/cdn/helpers/cdn-setup-letsencrypt.sh|g' "$file"
            echo "  ✓ Fixed: /usr/local/bin/cdn-setup-letsencrypt.sh -> /opt/scripts/cdn/helpers/cdn-setup-letsencrypt.sh" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
        
        # Pattern 6: Generic /usr/local/bin/cdn-*.sh in helpers directory -> /opt/scripts/cdn/helpers/
        if grep -q "/usr/local/bin/cdn-.*\.sh" "$file"; then
            sed -i 's|/usr/local/bin/\(cdn-[^[:space:]]*\.sh\)|/opt/scripts/cdn/helpers/\1|g' "$file"
            echo "  ✓ Fixed: Generic /usr/local/bin/cdn-*.sh patterns -> /opt/scripts/cdn/helpers/" >> "$CORRECTION_REPORT"
            ((corrections++))
        fi
    fi
    
    return $corrections
}

apply_path_corrections() {
    log_info "Applying path corrections to deployed files..."
    
    echo "CDN System Path Correction Report" > "$CORRECTION_REPORT"
    echo "Generated: $(date)" >> "$CORRECTION_REPORT"
    echo "========================================" >> "$CORRECTION_REPORT"
    
    # Correct paths in all shell scripts
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]] && [[ "$file" == *.sh ]]; then
            correct_paths_in_file "$file"
            if [[ $? -gt 0 ]]; then
                ((FILES_CORRECTED++))
            fi
        fi
    done < <(find "${DEPLOY_TARGET}" -type f -name "*.sh" -print0)
    
    # Correct paths in systemd service templates
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            correct_paths_in_file "$file"
            if [[ $? -gt 0 ]]; then
                ((FILES_CORRECTED++))
            fi
        fi
    done < <(find "${DEPLOY_TARGET}/templates/systemd" -type f 2>/dev/null -print0)
    
    log_success "Path corrections applied to ${FILES_CORRECTED} files"
    echo "" >> "$CORRECTION_REPORT"
    echo "Total files corrected: ${FILES_CORRECTED}" >> "$CORRECTION_REPORT"
}

################################################################################
# Directory structure creation
################################################################################

create_directory_structure() {
    log_info "Creating directory structure..."
    
    local -a directories=(
        "${DEPLOY_TARGET}"
        "${DEPLOY_TARGET}/helpers"
        "${DEPLOY_TARGET}/includes"
        "${DEPLOY_TARGET}/lib"
        "${DEPLOY_TARGET}/monitoring"
        "${DEPLOY_TARGET}/templates"
        "${DEPLOY_TARGET}/templates/nginx"
        "${DEPLOY_TARGET}/templates/systemd"
    )
    
    for dir in "${directories[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            exit 1
        fi
        chmod 755 "$dir"
    done
    
    log_success "Directory structure created"
}

################################################################################
# File deployment functions
################################################################################

deploy_file() {
    local src="$1"
    local dest="$2"
    local checksum
    
    # Copy file
    if ! cp "$src" "$dest"; then
        log_error "Failed to copy: $src -> $dest"
        return 1
    fi
    
    # Calculate checksum
    checksum=$(sha256sum "$dest" | awk '{print $1}')
    
    # Record in report
    echo "  File: $dest" >> "$REPORT_FILE"
    echo "    Permissions: $(stat -c '%a' "$dest")" >> "$REPORT_FILE"
    echo "    Owner: $(stat -c '%U:%G' "$dest")" >> "$REPORT_FILE"
    echo "    SHA256: $checksum" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    ((FILES_DEPLOYED++))
    return 0
}

deploy_main_scripts() {
    log_info "Deploying main scripts..."
    
    local -a main_scripts=(
        "cdn-initial-setup.sh"
        "cdn-tenant-manager.sh"
        "cdn-uninstall.sh"
        "cdn-monitoring-setup.sh"
    )
    
    for script in "${main_scripts[@]}"; do
        if [[ -f "${SOURCE_DIR}/${script}" ]]; then
            # Validate syntax first
            if ! validate_bash_syntax "${SOURCE_DIR}/${script}"; then
                log_error "Skipping ${script} due to syntax errors"
                continue
            fi
            
            deploy_file "${SOURCE_DIR}/${script}" "${DEPLOY_TARGET}/${script}"
            chmod 755 "${DEPLOY_TARGET}/${script}"
        else
            log_warning "Main script not found: ${script}"
        fi
    done
    
    log_success "Main scripts deployed"
}

deploy_helpers() {
    log_info "Deploying helper scripts..."
    
    if [[ ! -d "${SOURCE_DIR}/helpers" ]]; then
        log_warning "Helpers directory not found in source"
        return
    fi
    
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        
        # Validate syntax
        if ! validate_bash_syntax "$file"; then
            log_error "Skipping ${basename} due to syntax errors"
            continue
        fi
        
        deploy_file "$file" "${DEPLOY_TARGET}/helpers/${basename}"
        chmod 755 "${DEPLOY_TARGET}/helpers/${basename}"
    done < <(find "${SOURCE_DIR}/helpers" -maxdepth 1 -type f -name "*.sh" -print0)
    
    log_success "Helper scripts deployed"
}

deploy_includes() {
    log_info "Deploying include scripts..."
    
    if [[ ! -d "${SOURCE_DIR}/includes" ]]; then
        log_warning "Includes directory not found in source"
        return
    fi
    
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        
        # Validate syntax
        if ! validate_bash_syntax "$file"; then
            log_error "Skipping ${basename} due to syntax errors"
            continue
        fi
        
        deploy_file "$file" "${DEPLOY_TARGET}/includes/${basename}"
        chmod 755 "${DEPLOY_TARGET}/includes/${basename}"
    done < <(find "${SOURCE_DIR}/includes" -maxdepth 1 -type f -name "*.sh" -print0)
    
    log_success "Include scripts deployed"
}

deploy_lib() {
    log_info "Deploying library scripts..."
    
    if [[ ! -d "${SOURCE_DIR}/lib" ]]; then
        log_warning "Lib directory not found in source"
        return
    fi
    
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        
        # Validate syntax
        if ! validate_bash_syntax "$file"; then
            log_error "Skipping ${basename} due to syntax errors"
            continue
        fi
        
        deploy_file "$file" "${DEPLOY_TARGET}/lib/${basename}"
        chmod 755 "${DEPLOY_TARGET}/lib/${basename}"
    done < <(find "${SOURCE_DIR}/lib" -maxdepth 1 -type f -name "*.sh" -print0)
    
    log_success "Library scripts deployed"
}

deploy_monitoring() {
    log_info "Deploying monitoring scripts..."
    
    if [[ ! -d "${SOURCE_DIR}/monitoring" ]]; then
        log_warning "Monitoring directory not found in source"
        return
    fi
    
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        
        # Validate syntax
        if ! validate_bash_syntax "$file"; then
            log_error "Skipping ${basename} due to syntax errors"
            continue
        fi
        
        deploy_file "$file" "${DEPLOY_TARGET}/monitoring/${basename}"
        chmod 755 "${DEPLOY_TARGET}/monitoring/${basename}"
    done < <(find "${SOURCE_DIR}/monitoring" -maxdepth 1 -type f -name "*.sh" -print0)
    
    log_success "Monitoring scripts deployed"
}

deploy_templates() {
    log_info "Deploying template files..."
    
    if [[ ! -d "${SOURCE_DIR}/templates" ]]; then
        log_warning "Templates directory not found in source"
        return
    fi
    
    # Deploy root templates
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        deploy_file "$file" "${DEPLOY_TARGET}/templates/${basename}"
        chmod 644 "${DEPLOY_TARGET}/templates/${basename}"
    done < <(find "${SOURCE_DIR}/templates" -maxdepth 1 -type f -print0)
    
    # Deploy nginx templates
    if [[ -d "${SOURCE_DIR}/templates/nginx" ]]; then
        while IFS= read -r -d '' file; do
            local basename
            basename=$(basename "$file")
            deploy_file "$file" "${DEPLOY_TARGET}/templates/nginx/${basename}"
            chmod 644 "${DEPLOY_TARGET}/templates/nginx/${basename}"
        done < <(find "${SOURCE_DIR}/templates/nginx" -maxdepth 1 -type f -print0)
    fi
    
    # Deploy systemd templates
    if [[ -d "${SOURCE_DIR}/templates/systemd" ]]; then
        while IFS= read -r -d '' file; do
            local basename
            basename=$(basename "$file")
            deploy_file "$file" "${DEPLOY_TARGET}/templates/systemd/${basename}"
            chmod 644 "${DEPLOY_TARGET}/templates/systemd/${basename}"
        done < <(find "${SOURCE_DIR}/templates/systemd" -maxdepth 1 -type f -print0)
    fi
    
    log_success "Template files deployed"
}

################################################################################
# Symlink creation
################################################################################

create_symlinks() {
    log_info "Creating user command symlinks..."
    
    local -A symlinks=(
        ["cdn-initial-setup"]="${DEPLOY_TARGET}/cdn-initial-setup.sh"
        ["cdn-tenant-manager"]="${DEPLOY_TARGET}/cdn-tenant-manager.sh"
        ["cdn-uninstall"]="${DEPLOY_TARGET}/cdn-uninstall.sh"
        ["cdn-monitoring-setup"]="${DEPLOY_TARGET}/cdn-monitoring-setup.sh"
        ["cdn-setup-letsencrypt"]="${DEPLOY_TARGET}/helpers/cdn-setup-letsencrypt.sh"
    )
    
    for link_name in "${!symlinks[@]}"; do
        local target="${symlinks[$link_name]}"
        local link_path="${BIN_DIR}/${link_name}"
        
        # Remove existing symlink if present
        if [[ -L "$link_path" ]]; then
            rm -f "$link_path"
        elif [[ -e "$link_path" ]]; then
            log_warning "File exists at symlink location: $link_path (not a symlink)"
            continue
        fi
        
        # Create symlink
        if ln -s "$target" "$link_path"; then
            log_success "Created symlink: $link_name -> $target"
            echo "Symlink: $link_path -> $target" >> "$REPORT_FILE"
        else
            log_error "Failed to create symlink: $link_name"
        fi
    done
    
    log_success "Symlinks created"
}

################################################################################
# Validation
################################################################################

validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_passed=true
    
    # Check main scripts
    local -a main_scripts=(
        "cdn-initial-setup.sh"
        "cdn-tenant-manager.sh"
        "cdn-uninstall.sh"
        "cdn-monitoring-setup.sh"
    )
    
    for script in "${main_scripts[@]}"; do
        if [[ ! -x "${DEPLOY_TARGET}/${script}" ]]; then
            log_error "Main script not executable: ${script}"
            validation_passed=false
        fi
    done
    
    # Check symlinks
    local -a commands=(
        "cdn-initial-setup"
        "cdn-tenant-manager"
        "cdn-uninstall"
        "cdn-monitoring-setup"
        "cdn-setup-letsencrypt"
    )
    
    for cmd in "${commands[@]}"; do
        if [[ ! -L "${BIN_DIR}/${cmd}" ]]; then
            log_error "Symlink missing: ${cmd}"
            validation_passed=false
        fi
    done
    
    if [[ "$validation_passed" == true ]]; then
        log_success "Deployment validation passed"
        return 0
    else
        log_error "Deployment validation failed"
        return 1
    fi
}

################################################################################
# Reporting
################################################################################

generate_report() {
    log_info "Generating deployment report..."
    
    {
        echo ""
        echo "=========================================="
        echo "DEPLOYMENT SUMMARY"
        echo "=========================================="
        echo "Timestamp: $(date)"
        echo "Source Directory: ${SOURCE_DIR}"
        echo "Target Directory: ${DEPLOY_TARGET}"
        echo ""
        echo "Statistics:"
        echo "  Files Deployed: ${FILES_DEPLOYED}"
        echo "  Files Corrected: ${FILES_CORRECTED}"
        echo "  Errors: ${ERRORS}"
        echo ""
        
        if [[ -d "${BACKUP_DIR}" ]]; then
            echo "Backup Created: ${BACKUP_DIR}"
            echo ""
        fi
        
        echo "Available Commands:"
        echo "  cdn-initial-setup      - Initialize CDN system"
        echo "  cdn-tenant-manager     - Manage tenants"
        echo "  cdn-uninstall          - Remove CDN system"
        echo "  cdn-monitoring-setup   - Configure monitoring"
        echo "  cdn-setup-letsencrypt  - Setup SSL certificates"
        echo ""
        echo "Report Files:"
        echo "  Deployment: ${REPORT_FILE}"
        echo "  Corrections: ${CORRECTION_REPORT}"
        echo ""
    } | tee -a "$REPORT_FILE"
    
    log_success "Report generated: ${REPORT_FILE}"
}

display_final_status() {
    echo ""
    print_header "DEPLOYMENT COMPLETE"
    
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}✓ Deployment completed successfully${NC}"
        echo -e "${GREEN}✓ ${FILES_DEPLOYED} files deployed${NC}"
        echo -e "${GREEN}✓ ${FILES_CORRECTED} files had path corrections applied${NC}"
    else
        echo -e "${YELLOW}⚠ Deployment completed with ${ERRORS} errors${NC}"
        echo -e "${YELLOW}⚠ Please review the report for details${NC}"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "  1. Review deployment report: ${REPORT_FILE}"
    echo "  2. Review path corrections: ${CORRECTION_REPORT}"
    echo "  3. Run: cdn-initial-setup"
    echo ""
    
    if [[ $ERRORS -gt 0 ]]; then
        return 1
    fi
    return 0
}

################################################################################
# Main execution
################################################################################

main() {
    print_header "CDN SYSTEM DEPLOYMENT"
    
    # Initialize report
    {
        echo "CDN System Deployment Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""
    } > "$REPORT_FILE"
    
    # Pre-flight checks
    check_root
    check_source_directory
    check_dependencies
    
    # Handle existing installation
    prompt_for_backup
    
    # Create structure
    create_directory_structure
    
    # Deploy files
    deploy_main_scripts
    deploy_helpers
    deploy_includes
    deploy_lib
    deploy_monitoring
    deploy_templates
    
    # Apply path corrections
    apply_path_corrections
    
    # Create symlinks
    create_symlinks
    
    # Validate
    validate_deployment
    
    # Generate reports
    generate_report
    
    # Display final status
    display_final_status
    
    exit $?
}

# Execute main function
main "$@"
