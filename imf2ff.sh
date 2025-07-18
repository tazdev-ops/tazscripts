#!/bin/bash

# img2ff 2.0 - Image to Farbfeld Converter
# Original by mativ, enhanced version

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="img2ff"
readonly VERSION="2.0"

# Default settings
declare -a INPUT_PATHS=()
declare -i COMPRESS=0
declare -i QUIET=0
declare -i VALIDITY_CHECK=0
declare -i REMOVE_ORIGINAL=0
declare -i DRY_RUN=0
declare -i PARALLEL=0
declare -i PRESERVE_STRUCTURE=0
declare -i VERBOSE=0
declare -i PROCESSED=0
declare -i FAILED=0
declare -i SKIPPED=0

LOG_FILE=""
OUTPUT_DIR=""
COMPRESSION_METHOD="bzip2"
MAX_JOBS=$(nproc 2>/dev/null || echo 4)

# Supported formats (extensible)
readonly SUPPORTED_FORMATS="jpg jpeg png gif bmp tiff tif webp ppm pgm pbm"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    shift
    if [[ $QUIET -eq 0 ]]; then
        echo -e "${color}$*${NC}"
    fi
}

# Function to log messages
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    if [[ $VERBOSE -eq 1 ]] || [[ "$level" == "ERROR" && $QUIET -eq 0 ]]; then
        case "$level" in
            ERROR)   print_color "$RED" "[ERROR] $message" >&2 ;;
            WARNING) print_color "$YELLOW" "[WARNING] $message" ;;
            INFO)    print_color "$BLUE" "[INFO] $message" ;;
            SUCCESS) print_color "$GREEN" "[SUCCESS] $message" ;;
        esac
    fi
}

# Function to check dependencies
check_dependencies() {
    local deps=("convert" "identify")
    local missing=()
    
    # Check for farbfeld tools
    if ! command -v 2ff &> /dev/null; then
        if ! command -v png2ff &> /dev/null || ! command -v jpg2ff &> /dev/null; then
            missing+=("farbfeld tools (2ff, png2ff, jpg2ff)")
        fi
    fi
    
    # Check other dependencies
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    # Check compression tools
    case "$COMPRESSION_METHOD" in
        bzip2) command -v bzip2 &> /dev/null || missing+=("bzip2") ;;
        gzip)  command -v gzip &> /dev/null || missing+=("gzip") ;;
        xz)    command -v xz &> /dev/null || missing+=("xz") ;;
        zstd)  command -v zstd &> /dev/null || missing+=("zstd") ;;
    esac
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_color "$RED" "Missing dependencies: ${missing[*]}"
        print_color "$YELLOW" "Install with:"
        print_color "$YELLOW" "  - farbfeld: https://tools.suckless.org/farbfeld/"
        print_color "$YELLOW" "  - ImageMagick: sudo apt-get install imagemagick"
        print_color "$YELLOW" "  - Compression: sudo apt-get install bzip2 gzip xz-utils zstd"
        return 1
    fi
}

# Function to get output path
get_output_path() {
    local input_path="$1"
    local output_path
    
    if [[ -n "$OUTPUT_DIR" ]]; then
        if [[ $PRESERVE_STRUCTURE -eq 1 ]]; then
            # Preserve directory structure
            output_path="$OUTPUT_DIR/${input_path#./}"
        else
            # Flat structure
            output_path="$OUTPUT_DIR/$(basename "$input_path")"
        fi
    else
        output_path="$input_path"
    fi
    
    # Change extension
    output_path="${output_path%.*}.ff"
    
    # Add compression extension if needed
    if [[ $COMPRESS -eq 1 ]]; then
        case "$COMPRESSION_METHOD" in
            bzip2) output_path="${output_path}.bz2" ;;
            gzip)  output_path="${output_path}.gz" ;;
            xz)    output_path="${output_path}.xz" ;;
            zstd)  output_path="${output_path}.zst" ;;
        esac
    fi
    
    echo "$output_path"
}

# Function to convert a single image
convert_image() {
    local input_path="$1"
    local output_path=$(get_output_path "$input_path")
    local output_dir=$(dirname "$output_path")
    
    # Create output directory if needed
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            log_message "ERROR" "Failed to create directory: $output_dir"
            ((FAILED++))
            return 1
        }
    fi
    
    # Check if output already exists
    if [[ -f "$output_path" ]] && [[ $DRY_RUN -eq 0 ]]; then
        log_message "WARNING" "Output exists, skipping: $output_path"
        ((SKIPPED++))
        return 0
    fi
    
    # Validity check
    if [[ $VALIDITY_CHECK -eq 1 ]]; then
        if ! identify "$input_path" &> /dev/null; then
            log_message "ERROR" "Invalid image: $input_path"
            ((FAILED++))
            return 1
        fi
    fi
    
    # Dry run mode
    if [[ $DRY_RUN -eq 1 ]]; then
        print_color "$BLUE" "[DRY RUN] Would convert: $input_path -> $output_path"
        ((PROCESSED++))
        return 0
    fi
    
    log_message "INFO" "Converting: $input_path -> $output_path"
    
    # Perform conversion
    local temp_ff="${output_path}.tmp"
    local conversion_success=0
    
    # Try different conversion methods
    if command -v 2ff &> /dev/null; then
        2ff < "$input_path" > "$temp_ff" 2>/dev/null && conversion_success=1
    else
        # Fallback to format-specific converters or ImageMagick
        local ext="${input_path##*.}"
        ext="${ext,,}" # lowercase
        
        case "$ext" in
            png)
                if command -v png2ff &> /dev/null; then
                    png2ff < "$input_path" > "$temp_ff" 2>/dev/null && conversion_success=1
                fi
                ;;
            jpg|jpeg)
                if command -v jpg2ff &> /dev/null; then
                    jpg2ff < "$input_path" > "$temp_ff" 2>/dev/null && conversion_success=1
                fi
                ;;
        esac
        
        # Ultimate fallback: use ImageMagick
        if [[ $conversion_success -eq 0 ]]; then
            convert "$input_path" -depth 16 rgba:- 2>/dev/null | \
            awk 'BEGIN {
                # Read dimensions from ImageMagick
                getline dim < "/dev/stdin"
                split(dim, d, "x")
                w = d[1]; h = d[2]
                
                # Write farbfeld header
                printf "farbfeld"
                printf "%c%c%c%c", w/16777216, w/65536%256, w/256%256, w%256
                printf "%c%c%c%c", h/16777216, h/65536%256, h/256%256, h%256
            }
            {
                # Pass through pixel data
                print
            }' > "$temp_ff" && conversion_success=1
        fi
    fi
    
    if [[ $conversion_success -eq 0 ]]; then
        log_message "ERROR" "Failed to convert: $input_path"
        rm -f "$temp_ff"
        ((FAILED++))
        return 1
    fi
    
    # Apply compression if requested
    if [[ $COMPRESS -eq 1 ]]; then
        case "$COMPRESSION_METHOD" in
            bzip2) bzip2 -c "$temp_ff" > "$output_path" ;;
            gzip)  gzip -c "$temp_ff" > "$output_path" ;;
            xz)    xz -c "$temp_ff" > "$output_path" ;;
            zstd)  zstd -c "$temp_ff" > "$output_path" ;;
        esac
        rm -f "$temp_ff"
    else
        mv "$temp_ff" "$output_path"
    fi
    
    # Verify output was created
    if [[ ! -f "$output_path" ]]; then
        log_message "ERROR" "Failed to create output: $output_path"
        ((FAILED++))
        return 1
    fi
    
    # Remove original if requested
    if [[ $REMOVE_ORIGINAL -eq 1 ]]; then
        rm -f "$input_path"
        log_message "INFO" "Removed original: $input_path"
    fi
    
    log_message "SUCCESS" "Converted: $input_path"
    ((PROCESSED++))
    return 0
}

# Function to process files in parallel
process_parallel() {
    local -a files=("$@")
    local total=${#files[@]}
    local count=0
    
    export -f convert_image get_output_path log_message print_color
    export COMPRESS QUIET VALIDITY_CHECK REMOVE_ORIGINAL DRY_RUN
    export LOG_FILE OUTPUT_DIR COMPRESSION_METHOD PRESERVE_STRUCTURE VERBOSE
    export RED GREEN YELLOW BLUE NC
    
    printf "%s\0" "${files[@]}" | \
    xargs -0 -P "$MAX_JOBS" -I {} bash -c '
        convert_image "$@"
    ' -- {}
}

# Function to find and process images
process_path() {
    local path="$1"
    local -a images=()
    
    if [[ -f "$path" ]]; then
        # Single file
        local ext="${path##*.}"
        ext="${ext,,}" # lowercase
        
        if [[ " $SUPPORTED_FORMATS " =~ " $ext " ]]; then
            convert_image "$path"
        else
            log_message "WARNING" "Unsupported format: $path"
            ((SKIPPED++))
        fi
    elif [[ -d "$path" ]]; then
        # Directory
        local pattern=""
        for fmt in $SUPPORTED_FORMATS; do
            pattern+="-iname '*.${fmt}' -o "
        done
        pattern="${pattern% -o }" # Remove trailing -o
        
        while IFS= read -r -d '' file; do
            images+=("$file")
        done < <(find "$path" -type f \( $pattern \) -print0)
        
        if [[ ${#images[@]} -eq 0 ]]; then
            log_message "WARNING" "No supported images found in: $path"
            return
        fi
        
        print_color "$BLUE" "Found ${#images[@]} images in $path"
        
        if [[ $PARALLEL -eq 1 ]] && [[ ${#images[@]} -gt 1 ]]; then
            process_parallel "${images[@]}"
        else
            for img in "${images[@]}"; do
                convert_image "$img"
            done
        fi
    else
        log_message "ERROR" "Invalid path: $path"
        ((FAILED++))
    fi
}

# Function to print usage
print_usage() {
    cat << EOF
$SCRIPT_NAME $VERSION - Image to Farbfeld Format Converter

Usage: $SCRIPT_NAME [OPTIONS] [PATH...]

OPTIONS:
    -c              Enable compression (default: bzip2)
    -C METHOD       Set compression method (bzip2|gzip|xz|zstd)
    -d PATH         Add directory or image to process (can be used multiple times)
    -D              Dry run - show what would be done without doing it
    -h, --help      Display this help message
    -j JOBS         Number of parallel jobs (default: $(nproc))
    -l FILE         Enable logging to specified file
    -o DIR          Output directory (preserves structure with -p)
    -p              Preserve directory structure in output
    -P              Enable parallel processing
    -q              Quiet mode - suppress output
    -r              Remove original files after conversion
    -v              Enable verbose output
    -V              Enable image validity checking
    --version       Display version information

SUPPORTED FORMATS:
    $SUPPORTED_FORMATS

EXAMPLES:
    # Convert all images in a directory
    $SCRIPT_NAME -d /path/to/images

    # Convert with compression and parallel processing
    $SCRIPT_NAME -c -P -j 8 /path/to/images

    # Convert to specific output directory, preserving structure
    $SCRIPT_NAME -o /output/dir -p /input/dir

    # Dry run with validity checking
    $SCRIPT_NAME -D -V /path/to/images

    # Convert multiple paths with logging
    $SCRIPT_NAME -l conversion.log -d dir1 -d dir2 file1.png file2.jpg

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c)
                COMPRESS=1
                shift
                ;;
            -C)
                COMPRESS=1
                COMPRESSION_METHOD="$2"
                shift 2
                ;;
            -d)
                INPUT_PATHS+=("$2")
                shift 2
                ;;
            -D)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -j)
                MAX_JOBS="$2"
                PARALLEL=1
                shift 2
                ;;
            -l)
                LOG_FILE="$2"
                shift 2
                ;;
            -o)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -p)
                PRESERVE_STRUCTURE=1
                shift
                ;;
            -P)
                PARALLEL=1
                shift
                ;;
            -q)
                QUIET=1
                shift
                ;;
            -r)
                REMOVE_ORIGINAL=1
                shift
                ;;
            -v)
                VERBOSE=1
                shift
                ;;
            -V)
                VALIDITY_CHECK=1
                shift
                ;;
            --version)
                echo "$SCRIPT_NAME $VERSION"
                exit 0
                ;;
            -*)
                print_color "$RED" "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                INPUT_PATHS+=("$1")
                shift
                ;;
        esac
    done
}

# Main function
main() {
    parse_arguments "$@"
    
    # Check if we have any input
    if [[ ${#INPUT_PATHS[@]} -eq 0 ]]; then
        print_color "$RED" "Error: No input paths specified"
        print_usage
        exit 1
    fi
    
    # Initialize log file
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "=== $SCRIPT_NAME $VERSION - $(date) ===" > "$LOG_FILE"
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Create output directory if specified
    if [[ -n "$OUTPUT_DIR" ]] && [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR" || {
            print_color "$RED" "Failed to create output directory: $OUTPUT_DIR"
            exit 1
        }
    fi
    
    # Process all input paths
    local start_time=$(date +%s)
    
    for path in "${INPUT_PATHS[@]}"; do
        process_path "$path"
    done
    
    # Print summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $QUIET -eq 0 ]]; then
        echo
        print_color "$GREEN" "=== Conversion Summary ==="
        print_color "$GREEN" "Processed: $PROCESSED"
        print_color "$YELLOW" "Skipped: $SKIPPED"
        print_color "$RED" "Failed: $FAILED"
        print_color "$BLUE" "Duration: ${duration}s"
        
        if [[ -n "$LOG_FILE" ]]; then
            print_color "$BLUE" "Log file: $LOG_FILE"
        fi
    fi
    
    # Exit with error if any conversions failed
    [[ $FAILED -eq 0 ]] || exit 1
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
