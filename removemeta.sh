#!/usr/bin/env bash
# removemeta - Industrial-strength metadata removal tool
# Version: 2.0
# Supports: exiftool (perl), exiftool-rs, mat2
# Author: Enhanced for production use

set -euo pipefail
shopt -s nullglob

# Exit codes
readonly E_SUCCESS=0
readonly E_USAGE=1
readonly E_NOTOOL=2
readonly E_FILEACCESS=3
readonly E_TOOLERROR=4
readonly E_DISKSPACE=5

# Color codes (disabled if not a terminal)
if [[ -t 1 ]]; then
    readonly C_RED=$'\e[31m'
    readonly C_GREEN=$'\e[32m'
    readonly C_YELLOW=$'\e[33m'
    readonly C_BLUE=$'\e[34m'
    readonly C_RESET=$'\e[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi

# Global state
BACKEND=""
TOOL_CMD=""
KEEP_COPY=false
DRY_RUN=false
VERBOSE=false
QUIET=false
FORCE=false
RECURSIVE=false
BACKUP_DIR=""
STATS_PROCESSED=0
STATS_FAILED=0
STATS_SKIPPED=0

# Logging functions
log_error()   { [[ $QUIET == false ]] && printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_warn()    { [[ $QUIET == false ]] && printf '%s[WARN]%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_info()    { [[ $QUIET == false ]] && printf '%s[INFO]%s  %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_success() { [[ $QUIET == false ]] && printf '%s[OK]%s    %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_verbose() { [[ $VERBOSE == true ]] && printf '[DEBUG] %s\n' "$*"; }

# Enhanced usage
usage() {
    cat <<'EOF'
removemeta - Remove metadata from files safely and efficiently

USAGE:
    removemeta [OPTIONS] <file1> [file2 ...]

OPTIONS:
    -k, --keep      Keep original, create <name>-nometa.<ext>
    -n, --dry-run   Show what would be done without doing it
    -v, --verbose   Show detailed progress
    -q, --quiet     Suppress all output except errors
    -f, --force     Don't prompt for confirmation
    -r, --recursive Process directories recursively
    -b, --backup    Create backup in ~/.removemeta-backups/
    -h, --help      Show this help

EXAMPLES:
    removemeta photo.jpg                    # Remove metadata in-place
    removemeta -k *.pdf                     # Keep originals, create clean copies
    removemeta -r -n ~/Documents/           # Dry-run on entire directory
    removemeta -b sensitive.docx            # Backup before cleaning

SUPPORTED TOOLS (auto-detected):
    1. exiftool    - Best compatibility (JPEG, PNG, PDF, Office, etc.)
    2. exiftool-rs - Fast Rust implementation
    3. mat2        - Privacy-focused (supports fewer formats)

EXIT CODES:
    0 - Success
    1 - Usage error
    2 - No metadata tool found
    3 - File access error
    4 - Tool execution error
    5 - Insufficient disk space
EOF
    exit "${1:-$E_USAGE}"
}

# Parse command-line arguments
parse_args() {
    local args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--keep)      KEEP_COPY=true ;;
            -n|--dry-run)   DRY_RUN=true ;;
            -v|--verbose)   VERBOSE=true ;;
            -q|--quiet)     QUIET=true; VERBOSE=false ;;
            -f|--force)     FORCE=true ;;
            -r|--recursive) RECURSIVE=true ;;
            -b|--backup)    BACKUP_DIR="$HOME/.removemeta-backups/$(date +%Y%m%d-%H%M%S)" ;;
            -h|--help)      usage 0 ;;
            -*)             log_error "Unknown option: $1"; usage ;;
            *)              args+=("$1") ;;
        esac
        shift
    done
    
    # Restore positional parameters
    set -- "${args[@]}"
    
    # Validate
    if [[ ${#args[@]} -eq 0 ]]; then
        log_error "No files specified"
        usage
    fi
    
    # Store files globally for processing
    FILES=("${args[@]}")
}

# Detect available backend
detect_backend() {
    log_verbose "Detecting available metadata removal tools..."
    
    # Test for Perl exiftool (has -ver command)
    if command -v exiftool >/dev/null 2>&1; then
        if exiftool -ver >/dev/null 2>&1; then
            BACKEND="PERL"
            TOOL_CMD="exiftool"
            log_verbose "Found Perl ExifTool $(exiftool -ver 2>/dev/null || echo 'unknown version')"
            return
        fi
    fi
    
    # Test for Rust exiftool-rs
    if command -v exiftool-rs >/dev/null 2>&1; then
        BACKEND="RUST"
        TOOL_CMD="exiftool-rs"
        log_verbose "Found exiftool-rs (Rust implementation)"
        return
    fi
    
    # Test for mat2
    if command -v mat2 >/dev/null 2>&1; then
        BACKEND="MAT2"
        TOOL_CMD="mat2"
        log_verbose "Found mat2 $(mat2 --version 2>/dev/null | head -1 || echo 'unknown version')"
        return
    fi
    
    log_error "No metadata removal tool found!"
    log_error "Please install one of: exiftool, exiftool-rs, or mat2"
    log_error ""
    log_error "Installation commands:"
    log_error "  Arch:   sudo pacman -S perl-image-exiftool  (or)  yay -S exiftool-rs"
    log_error "  Debian: sudo apt install exiftool mat2"
    log_error "  macOS:  brew install exiftool"
    exit $E_NOTOOL
}

# Check disk space (rough estimate)
check_disk_space() {
    local file=$1
    local needed_kb
    
    [[ $KEEP_COPY == false ]] && return 0  # In-place needs no extra space
    
    if [[ -f $file ]]; then
        needed_kb=$(( ($(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0) + 1023) / 1024 ))
        local avail_kb
        avail_kb=$(df -Pk "$(dirname "$file")" | awk 'NR==2 {print $4}')
        
        if [[ $needed_kb -gt $avail_kb ]]; then
            log_error "Insufficient disk space for $file (need ${needed_kb}KB, have ${avail_kb}KB)"
            return $E_DISKSPACE
        fi
    fi
    return 0
}

# Create backup if requested
backup_file() {
    local file=$1
    [[ -z $BACKUP_DIR ]] && return 0
    
    mkdir -p "$BACKUP_DIR"
    local backup_path="$BACKUP_DIR/$(basename "$file")"
    
    log_verbose "Backing up to: $backup_path"
    cp -p "$file" "$backup_path" || {
        log_error "Failed to create backup of $file"
        return $E_FILEACCESS
    }
}

# Process file with Perl ExifTool
process_perl_exiftool() {
    local file=$1
    local output_file="$file"
    local temp_file=""
    
    if [[ $KEEP_COPY == true ]]; then
        output_file="${file%.*}-nometa.${file##*.}"
        cp -p "$file" "$output_file" || return $E_FILEACCESS
    else
        # Use atomic operation: work on temp file, then move
        temp_file="${file}.removemeta.tmp.$$"
        cp -p "$file" "$temp_file" || return $E_FILEACCESS
        output_file="$temp_file"
    fi
    
    if $TOOL_CMD -overwrite_original -all= "$output_file" >/dev/null 2>&1; then
        if [[ -n $temp_file ]]; then
            mv -f "$temp_file" "$file" || {
                rm -f "$temp_file"
                return $E_FILEACCESS
            }
        fi
        return 0
    else
        [[ -n $temp_file ]] && rm -f "$temp_file"
        [[ $KEEP_COPY == true ]] && rm -f "$output_file"
        return $E_TOOLERROR
    fi
}

# Process file with Rust exiftool-rs
process_rust_exiftool() {
    local file=$1
    local temp_file=""
    
    if [[ $KEEP_COPY == true ]]; then
        local output_file="${file%.*}-nometa.${file##*.}"
        if $TOOL_CMD --output "$output_file" "$file" >/dev/null 2>&1; then
            return 0
        else
            rm -f "$output_file"
            return $E_TOOLERROR
        fi
    else
        # exiftool-rs doesn't have atomic in-place, so we do it manually
        temp_file="${file}.removemeta.tmp.$$"
        if $TOOL_CMD --output "$temp_file" "$file" >/dev/null 2>&1; then
            mv -f "$temp_file" "$file" || {
                rm -f "$temp_file"
                return $E_FILEACCESS
            }
            return 0
        else
            rm -f "$temp_file"
            return $E_TOOLERROR
        fi
    fi
}

# Process file with mat2
process_mat2() {
    local file=$1
    
    if [[ $KEEP_COPY == true ]]; then
        local output_file="${file%.*}-nometa.${file##*.}"
        if $TOOL_CMD --no-sandbox -o "$output_file" "$file" >/dev/null 2>&1; then
            return 0
        else
            rm -f "$output_file"
            return $E_TOOLERROR
        fi
    else
        if $TOOL_CMD --no-sandbox --inplace "$file" >/dev/null 2>&1; then
            return 0
        else
            return $E_TOOLERROR
        fi
    fi
}

# Main file processor
process_file() {
    local file=$1
    local basename
    basename=$(basename "$file")
    
    # Pre-flight checks
    if [[ ! -e $file ]]; then
        log_warn "File not found: $file"
        ((STATS_SKIPPED++))
        return
    fi
    
    if [[ -L $file ]]; then
        log_warn "Skipping symlink: $file"
        ((STATS_SKIPPED++))
        return
    fi
    
    if [[ -d $file ]]; then
        if [[ $RECURSIVE == true ]]; then
            log_verbose "Entering directory: $file"
            local f
            for f in "$file"/*; do
                [[ -e $f ]] && process_file "$f"
            done
        else
            log_warn "Skipping directory: $file (use -r for recursive)"
            ((STATS_SKIPPED++))
        fi
        return
    fi
    
    if [[ ! -f $file ]]; then
        log_warn "Not a regular file: $file"
        ((STATS_SKIPPED++))
        return
    fi
    
    if [[ ! -r $file ]]; then
        log_error "Cannot read: $file"
        ((STATS_FAILED++))
        return
    fi
    
    if [[ $KEEP_COPY == false && ! -w $file ]]; then
        log_error "Cannot write: $file"
        ((STATS_FAILED++))
        return
    fi
    
    # Check disk space
    if ! check_disk_space "$file"; then
        ((STATS_FAILED++))
        return
    fi
    
    # Dry run - just show what would happen
    if [[ $DRY_RUN == true ]]; then
        if [[ $KEEP_COPY == true ]]; then
            log_info "[DRY RUN] Would create: ${file%.*}-nometa.${file##*.}"
        else
            log_info "[DRY RUN] Would clean: $file"
        fi
        ((STATS_PROCESSED++))
        return
    fi
    
    # Create backup if requested
    if ! backup_file "$file"; then
        log_error "Backup failed for: $file"
        ((STATS_FAILED++))
        return
    fi
    
    # Process the file
    log_verbose "Processing: $file"
    local exit_code=0
    
    case $BACKEND in
        PERL) process_perl_exiftool "$file"; exit_code=$? ;;
        RUST) process_rust_exiftool "$file"; exit_code=$? ;;
        MAT2) process_mat2 "$file"; exit_code=$? ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        if [[ $KEEP_COPY == true ]]; then
            log_success "Created: ${file%.*}-nometa.${file##*.}"
        else
            log_success "Cleaned: $file"
        fi
        ((STATS_PROCESSED++))
    else
        case $exit_code in
            $E_FILEACCESS) log_error "File access error: $file" ;;
            $E_TOOLERROR)  log_error "Tool failed on: $file (possibly unsupported format)" ;;
            *)             log_error "Unknown error: $file" ;;
        esac
        ((STATS_FAILED++))
    fi
}

# Show summary
show_summary() {
    [[ $QUIET == true ]] && return
    
    local total=$((STATS_PROCESSED + STATS_FAILED + STATS_SKIPPED))
    
    echo
    log_info "Summary:"
    log_info "  Total files: $total"
    [[ $STATS_PROCESSED -gt 0 ]] && log_success "  Processed: $STATS_PROCESSED"
    [[ $STATS_FAILED -gt 0 ]]    && log_error "  Failed: $STATS_FAILED"
    [[ $STATS_SKIPPED -gt 0 ]]   && log_warn "  Skipped: $STATS_SKIPPED"
    
    if [[ -n $BACKUP_DIR && -d $BACKUP_DIR ]]; then
        log_info "  Backups saved to: $BACKUP_DIR"
    fi
}

# Confirmation prompt
confirm_action() {
    [[ $FORCE == true ]] && return 0
    [[ $DRY_RUN == true ]] && return 0
    
    local file_count=${#FILES[@]}
    local action="remove metadata from"
    [[ $KEEP_COPY == true ]] && action="create clean copies of"
    
    if [[ $file_count -gt 3 ]]; then
        printf '%sAbout to %s %d files. Continue? [y/N] %s' \
               "$C_YELLOW" "$action" "$file_count" "$C_RESET"
        read -r response
        [[ $response =~ ^[Yy] ]] || exit $E_SUCCESS
    fi
}

# Main execution
main() {
    parse_args "$@"
    detect_backend
    
    log_info "Using backend: $BACKEND ($TOOL_CMD)"
    [[ $DRY_RUN == true ]] && log_warn "DRY RUN MODE - no files will be modified"
    
    confirm_action
    
    # Process all files
    for file in "${FILES[@]}"; do
        process_file "$file"
    done
    
    show_summary
    
    # Exit with error if any files failed
    [[ $STATS_FAILED -gt 0 ]] && exit $E_TOOLERROR
    exit $E_SUCCESS
}

# Signal handlers for cleanup
cleanup() {
    # Remove any temp files on interrupt
    rm -f /tmp/*.removemeta.tmp.$$ 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Run the script
main "$@"
