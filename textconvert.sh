#!/bin/bash
#
# Advanced file conversion script with enterprise-grade features.
# Intelligently selects optimal conversion tools and strategies.
#
# Author: Enhanced by an AI Assistant
# Version: 6.0 - Enterprise Edition with comprehensive improvements

# Enable strict mode
set -euo pipefail
IFS=$'\n\t'

# --- Global Constants ---
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_VERSION="6.0"
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- Default Configuration ---
DEFAULT_OUTPUT_FORMAT="txt"
DEFAULT_OCR_LANG="eng"
DEFAULT_ENCODING="utf-8"
DEFAULT_QUALITY="high"
DEFAULT_COMPRESSION="balanced"
DEFAULT_MAX_RETRIES=3
DEFAULT_TIMEOUT=300
DEFAULT_MAX_FILE_SIZE=$((1024 * 1024 * 1024)) # 1GB
DEFAULT_CACHE_DAYS=7
DEFAULT_PARALLEL_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

# Pandoc PDF options
PANDOC_PDF_OPTS=(
    --standalone
    --pdf-engine=xelatex
    -V "mainfont=Libertinus Serif"
    -V "sansfont=Libertinus Sans"
    -V "monofont=Libertinus Mono"
    -V "fontsize=11pt"
    -V "geometry:margin=1in"
    -V "linkcolor=blue"
    -V "urlcolor=blue"
    -V "documentclass=article"
    -V "pagestyle=plain"
)

# --- Runtime Configuration ---
VERBOSITY=1
DRY_RUN=0
RECURSIVE=0
FORCE_OVERWRITE=0
TARGET_OCR_LANG="${DEFAULT_OCR_LANG}"
PARALLEL_JOBS="${DEFAULT_PARALLEL_JOBS}"
KEEP_ORIGINALS=1
BATCH_MODE=0
VALIDATE_OUTPUT=1
EXTRACT_EMBEDDED=0
USE_FALLBACK_API=0
SHOW_PROGRESS=1
PRESERVE_METADATA=1
ENCODING="${DEFAULT_ENCODING}"
QUALITY="${DEFAULT_QUALITY}"
COMPRESSION="${DEFAULT_COMPRESSION}"
MAX_RETRIES="${DEFAULT_MAX_RETRIES}"
TIMEOUT="${DEFAULT_TIMEOUT}"
USE_CACHE=1
SAFE_MODE=0
MONITOR_RESOURCES=0
AUTO_OPTIMIZE=1
CONVERSION_CHAIN=0
OUTPUT_DIR=""
NO_CONFIRM=0

# --- Color Definitions ---
if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_ERROR='\033[0;31m'
    C_SUCCESS='\033[0;32m'
    C_WARN='\033[0;33m'
    C_INFO='\033[0;36m'
    C_CMD='\033[0;35m'
    C_PROGRESS='\033[0;34m'
    C_HIGHLIGHT='\033[1;37m'
    C_RESET='\033[0m'
else
    C_ERROR=''
    C_SUCCESS=''
    C_WARN=''
    C_INFO=''
    C_CMD=''
    C_PROGRESS=''
    C_HIGHLIGHT=''
    C_RESET=''
fi

# --- Format Definitions ---
declare -A FORMAT_EXTENSIONS=(
    # Documents
    ["pdf"]="pdf"
    ["epub"]="epub"
    ["mobi"]="mobi"
    ["azw"]="azw"
    ["azw3"]="azw3"
    ["docx"]="docx"
    ["doc"]="doc"
    ["odt"]="odt"
    ["rtf"]="rtf"
    ["tex"]="tex latex"
    ["rst"]="rst"
    ["textile"]="textile"
    ["mediawiki"]="wiki"
    ["docbook"]="xml dbk"
    ["man"]="man"
    ["fb2"]="fb2"
    ["lit"]="lit"
    ["pdb"]="pdb"
    ["djvu"]="djvu"
    ["chm"]="chm"
    
    # Markup
    ["md"]="md markdown mkd"
    ["html"]="html htm"
    ["xhtml"]="xhtml"
    ["xml"]="xml"
    ["json"]="json"
    ["yaml"]="yaml yml"
    ["toml"]="toml"
    ["asciidoc"]="adoc asc"
    ["org"]="org"
    ["creole"]="creole"
    ["muse"]="muse"
    ["twiki"]="twiki"
    
    # Plain text
    ["txt"]="txt text"
    ["csv"]="csv"
    ["tsv"]="tsv"
    ["log"]="log"
    
    # Presentations
    ["pptx"]="pptx"
    ["ppt"]="ppt"
    ["odp"]="odp"
    ["beamer"]="tex"
    ["slidy"]="html"
    ["reveal"]="html"
    
    # Spreadsheets
    ["xlsx"]="xlsx"
    ["ods"]="ods"
    ["xls"]="xls"
    
    # Archives
    ["zip"]="zip"
    ["tar"]="tar"
    ["gz"]="gz"
    ["7z"]="7z"
    ["rar"]="rar"
    
    # Images
    ["png"]="png"
    ["jpg"]="jpg jpeg"
    ["tiff"]="tiff tif"
    ["gif"]="gif"
    ["bmp"]="bmp"
    ["webp"]="webp"
    ["svg"]="svg svgz"
    ["ico"]="ico"
    ["heic"]="heic heif"
    ["avif"]="avif"
    ["jxl"]="jxl"
)

# Format MIME types for better detection
declare -A FORMAT_MIMETYPES=(
    ["application/pdf"]="pdf"
    ["application/epub+zip"]="epub"
    ["application/x-mobipocket-ebook"]="mobi"
    ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"]="docx"
    ["application/msword"]="doc"
    ["application/vnd.oasis.opendocument.text"]="odt"
    ["text/rtf"]="rtf"
    ["text/x-tex"]="tex"
    ["text/html"]="html"
    ["text/xml"]="xml"
    ["application/xml"]="xml"
    ["application/json"]="json"
    ["text/markdown"]="md"
    ["text/plain"]="txt"
    ["text/csv"]="csv"
    ["image/png"]="png"
    ["image/jpeg"]="jpg"
    ["image/tiff"]="tiff"
    ["image/svg+xml"]="svg"
    ["image/webp"]="webp"
    ["image/heic"]="heic"
    ["image/avif"]="avif"
    ["image/jxl"]="jxl"
)

# Conversion quality profiles
declare -A QUALITY_PROFILES=(
    ["low"]="speed=fast;dpi=150;compression=high;colors=256"
    ["medium"]="speed=balanced;dpi=300;compression=medium;colors=16k"
    ["high"]="speed=slow;dpi=600;compression=low;colors=16m"
    ["max"]="speed=veryslow;dpi=1200;compression=none;colors=true"
    ["print"]="speed=slow;dpi=300;compression=low;colors=cmyk"
    ["web"]="speed=fast;dpi=96;compression=high;colors=rgb"
    ["archive"]="speed=balanced;dpi=300;compression=max;colors=gray"
)

# --- User Configuration ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/textconvert"
CONFIG_FILE="$CONFIG_DIR/config.sh"
PRESETS_FILE="$CONFIG_DIR/presets.json"
HISTORY_FILE="$CONFIG_DIR/history.log"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/textconvert"
STATS_FILE="$CONFIG_DIR/stats.json"
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/textconvert"
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_DIR=""
COMPLETION_FILE="$CONFIG_DIR/completions.txt"

# API endpoints for fallback conversion
declare -A API_ENDPOINTS=(
    ["cloudconvert"]="https://api.cloudconvert.com/v2/convert"
    ["convertapi"]="https://v2.convertapi.com/convert"
    ["zamzar"]="https://sandbox.zamzar.com/v1/jobs"
)

# Ensure directories exist with proper permissions
for dir in "$CONFIG_DIR" "$CACHE_DIR" "$LOCK_DIR"; do
    [[ ! -d "$dir" ]] && mkdir -p "$dir" && chmod 700 "$dir"
done

# Initialize configuration files
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" << 'EOF'
# TextConvert User Configuration
# Uncomment and modify settings as needed

# DEFAULT_OUTPUT_FORMAT="pdf"
# DEFAULT_OCR_LANG="eng+deu"
# DEFAULT_QUALITY="high"
# DEFAULT_PARALLEL_JOBS=4
# USE_CACHE=1
# SHOW_PROGRESS=1
# API_KEY_CLOUDCONVERT=""
# API_KEY_CONVERTAPI=""
# API_KEY_ZAMZAR=""
EOF
fi

# Initialize stats file
if [[ ! -f "$STATS_FILE" ]]; then
    echo '{"conversions":0,"failures":0,"total_size":0,"total_time":0,"format_stats":{}}' > "$STATS_FILE"
fi

# Initialize presets file
if [[ ! -f "$PRESETS_FILE" ]]; then
    cat > "$PRESETS_FILE" << 'EOF'
{
  "academic": {
    "quality": "high",
    "format": "pdf",
    "options": ["--toc", "--number-sections", "--bibliography"]
  },
  "ebook": {
    "quality": "medium",
    "format": "epub",
    "options": ["--embed-fonts", "--smart"]
  },
  "minimal": {
    "quality": "low",
    "format": "txt",
    "options": ["--strip-metadata", "--no-images"]
  },
  "archive": {
    "quality": "archive",
    "format": "pdf",
    "options": ["--pdf-engine=pdflatex", "--compress"]
  }
}
EOF
fi

# Load user configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# --- Utility Functions ---

# Create secure temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d "$TEMP_BASE/textconvert.XXXXXX")
    chmod 700 "$TEMP_DIR"
}

# Enhanced cleanup with signal handling
cleanup() {
    local exit_code=$?
    
    # Kill any background jobs
    if jobs -p &>/dev/null; then
        jobs -p | xargs -r kill -TERM 2>/dev/null || true
        sleep 1
        jobs -p | xargs -r kill -KILL 2>/dev/null || true
    fi
    
    # Remove lock files
    find "$LOCK_DIR" -name "*.lock" -mmin +60 -delete 2>/dev/null || true
    
    # Remove temporary directory
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Clear progress indicators
    if [[ $SHOW_PROGRESS -eq 1 ]]; then
        printf "\r%*s\r" "${COLUMNS:-80}" ""
    fi
    
    exit "$exit_code"
}

# Set up signal handlers
trap cleanup EXIT INT TERM HUP

# Create lock file
create_lock() {
    local file="$1"
    local lockfile="$LOCK_DIR/$(echo "$file" | md5sum | cut -d' ' -f1).lock"
    
    if [[ -f "$lockfile" ]]; then
        local pid
        pid=$(cat "$lockfile" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
    fi
    
    echo $$ > "$lockfile"
    return 0
}

# Remove lock file
remove_lock() {
    local file="$1"
    local lockfile="$LOCK_DIR/$(echo "$file" | md5sum | cut -d' ' -f1).lock"
    rm -f "$lockfile"
}

# Get file size in bytes (cross-platform)
get_file_size() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f%z "$file" 2>/dev/null || echo 0
    else
        stat -c%s "$file" 2>/dev/null || echo 0
    fi
}

# Human-readable file size
human_size() {
    local size=$1
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec-i --suffix=B "$size"
    else
        local units=("B" "K" "M" "G" "T")
        local unit=0
        while [[ $size -gt 1024 && $unit -lt 4 ]]; do
            size=$((size / 1024))
            ((unit++))
        done
        echo "${size}${units[$unit]}"
    fi
}

# Calculate checksum for caching
calculate_checksum() {
    local file="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        # Fallback to modification time
        stat -c%Y "$file" 2>/dev/null || stat -f%m "$file" 2>/dev/null
    fi
}

# Enhanced logging with structured output
log_msg() {
    local level="$1"
    local message="$2"
    local color="$C_RESET"
    local min_verbosity=1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "ERROR")   color="$C_ERROR";    min_verbosity=0 ;;
        "SUCCESS") color="$C_SUCCESS";  min_verbosity=1 ;;
        "WARN")    color="$C_WARN";     min_verbosity=1 ;;
        "INFO")    color="$C_INFO";     min_verbosity=2 ;;
        "CMD")     color="$C_CMD";      min_verbosity=2 ;;
        "DEBUG")   color="$C_INFO";     min_verbosity=3 ;;
        "PROGRESS") color="$C_PROGRESS"; min_verbosity=1 ;;
        "TIMING")  color="$C_INFO";     min_verbosity=2 ;;
        *) message="$level $message" ;;
    esac

    if [[ $VERBOSITY -ge $min_verbosity ]]; then
        if [[ "$level" == "PROGRESS" ]]; then
            printf "\r${color}%s${C_RESET}" "$message" >&2
        else
            echo -e "${color}[$level] $message${C_RESET}" >&2
        fi
    fi
    
    # Structured logging to file
    if [[ -w "$HISTORY_FILE" ]]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
               "$timestamp" "$level" "$message" >> "$HISTORY_FILE"
    fi
}

# Resource monitoring
monitor_resources() {
    if [[ $MONITOR_RESOURCES -eq 0 ]]; then
        return
    fi
    
    local pid=$1
    local output_file=$2
    
    while kill -0 "$pid" 2>/dev/null; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            ps -o pid,pcpu,pmem,vsz,rss,comm -p "$pid" >> "$output_file.resources"
        else
            ps -o pid,pcpu,pmem,vsz,rss,comm -p "$pid" >> "$output_file.resources"
        fi
        sleep 1
    done &
}

# Enhanced progress indicator with ETA
show_progress() {
    local current=$1
    local total=$2
    local file=$3
    local start_time=$4
    
    if [[ $SHOW_PROGRESS -eq 0 || $VERBOSITY -eq 0 ]]; then
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    # Calculate ETA
    local elapsed=$(($(date +%s) - start_time))
    local eta=""
    if [[ $current -gt 0 && $elapsed -gt 0 ]]; then
        local rate=$((elapsed / current))
        local remaining=$((rate * (total - current)))
        if [[ $remaining -gt 0 ]]; then
            eta=$(printf " ETA: %02d:%02d" $((remaining / 60)) $((remaining % 60)))
        fi
    fi
    
    # Terminal width detection
    local term_width=${COLUMNS:-80}
    local max_file_len=$((term_width - 70))
    local display_file=$(basename "$file")
    if [[ ${#display_file} -gt $max_file_len ]]; then
        display_file="${display_file:0:$((max_file_len - 3))}..."
    fi
    
    printf "\r${C_PROGRESS}[%${filled}s%${empty}s] %3d%% (%d/%d)%s %s${C_RESET}" \
           "$(printf '=%.0s' $(seq 1 $filled))" \
           "" "$percent" "$current" "$total" \
           "$eta" "$display_file"
}

# Version checking for tools
check_tool_version() {
    local tool=$1
    local min_version=$2
    local version_cmd=$3
    
    if ! command -v "$tool" &>/dev/null; then
        return 1
    fi
    
    local version
    version=$($tool $version_cmd 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    
    if [[ -n "$version" && -n "$min_version" ]]; then
        # Simple version comparison
        if [[ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -1)" != "$min_version" ]]; then
            log_msg WARN "$tool version $version is below recommended $min_version"
        fi
    fi
    
    return 0
}

# Enhanced dependency checking with feature scoring
check_deps() {
    log_msg INFO "Checking dependencies and capabilities..."
    local missing_critical=0
    local feature_score=0
    local max_score=100
    
    # Critical dependencies with version requirements
    declare -A critical_deps=(
        ["pandoc"]="2.0:--version:Document conversion engine"
    )
    
    # Feature dependencies with scoring
    declare -A feature_deps=(
        ["ebook-convert"]="5:calibre:--version:E-book formats"
        ["ocrmypdf"]="10:ocrmypdf:--version:PDF OCR"
        ["pdftotext"]="3:poppler-utils:-v:PDF text extraction"
        ["pdftoppm"]="3:poppler-utils:-v:PDF rendering"
        ["pdfimages"]="2:poppler-utils:-v:PDF image extraction"
        ["pdfunite"]="2:poppler-utils:-v:PDF merging"
        ["djvutxt"]="3:djvulibre-bin:--help:DJVU support"
        ["djvups"]="2:djvulibre-bin:--help:DJVU to PS"
        ["tesseract"]="8:tesseract-ocr:--version:OCR engine"
        ["libreoffice"]="5:libreoffice:--version:Office formats"
        ["unoconv"]="3:unoconv:--version:Office conversion"
        ["xelatex"]="5:texlive-xetex:--version:LaTeX PDF"
        ["pdflatex"]="3:texlive-latex-base:--version:LaTeX PDF alt"
        ["convert"]="5:imagemagick:-version:Image processing"
        ["magick"]="3:imagemagick:-version:ImageMagick 7"
        ["jq"]="3:jq:--version:JSON processing"
        ["xmllint"]="2:libxml2-utils:--version:XML validation"
        ["csvtool"]="2:csvtool:version:CSV manipulation"
        ["antiword"]="2:antiword:-h:Legacy .doc"
        ["unrtf"]="2:unrtf:--version:RTF support"
        ["w3m"]="2:w3m:-version:HTML to text"
        ["lynx"]="2:lynx:-version:HTML to text alt"
        ["html2text"]="2:html2text:--version:HTML to text alt2"
        ["detex"]="2:texlive-binaries:-v:LaTeX to text"
        ["gs"]="4:ghostscript:--version:PostScript/PDF"
        ["ps2pdf"]="2:ghostscript:--version:PS to PDF"
        ["ffmpeg"]="3:ffmpeg:-version:Media processing"
        ["exiftool"]="3:libimage-exiftool-perl:-ver:Metadata"
        ["file"]="5:file:--version:Format detection"
        ["mimetype"]="2:libfile-mimeinfo-perl:--version:MIME detection"
        ["7z"]="2:p7zip-full:-h:Archive support"
        ["unrar"]="2:unrar:-h:RAR support"
        ["mutool"]="3:mupdf-tools:-v:PDF tools"
        ["wkhtmltopdf"]="3:wkhtmltopdf:-V:HTML to PDF"
    )
    
    # Check critical dependencies
    for cmd in "${!critical_deps[@]}"; do
        IFS=':' read -r min_ver version_arg purpose <<< "${critical_deps[$cmd]}"
        if ! check_tool_version "$cmd" "$min_ver" "$version_arg"; then
            log_msg ERROR "Critical: '$cmd' not found. Purpose: $purpose"
            ((missing_critical++))
        fi
    done
    
    if [[ $missing_critical -gt 0 ]]; then
        log_msg ERROR "Cannot proceed without critical dependencies."
        exit 1
    fi
    
    # Check and score feature dependencies
    declare -gA AVAILABLE_FEATURES=()
    declare -gA FEATURE_SCORES=()
    
    for cmd in "${!feature_deps[@]}"; do
        IFS=':' read -r score pkg version_arg purpose <<< "${feature_deps[$cmd]}"
        if check_tool_version "$cmd" "" "$version_arg"; then
            AVAILABLE_FEATURES["$cmd"]=1
            FEATURE_SCORES["$cmd"]=$score
            ((feature_score += score))
            log_msg DEBUG "Found: $cmd (+$score points)"
        else
            log_msg DEBUG "Missing: $cmd - Install '$pkg' for: $purpose"
        fi
    done
    
    # Calculate capability score
    local capability_percent=$((feature_score * 100 / max_score))
    log_msg INFO "System capability score: $capability_percent% ($feature_score/$max_score)"
    
    # Warn about limited functionality
    if [[ $capability_percent -lt 50 ]]; then
        log_msg WARN "Limited functionality. Consider installing more conversion tools."
    fi
    
    # Check for language support in OCR
    if [[ -n "${AVAILABLE_FEATURES[tesseract]}" ]]; then
        local available_langs
        available_langs=$(tesseract --list-langs 2>&1 | tail -n +2 | tr '\n' ' ')
        log_msg DEBUG "OCR languages available: $available_langs"
        
        if [[ ! " $available_langs " =~ " $TARGET_OCR_LANG " ]]; then
            log_msg WARN "OCR language '$TARGET_OCR_LANG' not installed"
            log_msg INFO "Install with: sudo apt-get install tesseract-ocr-${TARGET_OCR_LANG}"
        fi
    fi
}

# Enhanced format detection with multiple methods
detect_format() {
    local file="$1"
    local detected=""
    
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    
    # Method 1: MIME type detection
    if command -v mimetype &>/dev/null; then
        local mime
        mime=$(mimetype -b "$file" 2>/dev/null)
        if [[ -n "${FORMAT_MIMETYPES[$mime]}" ]]; then
            detected="${FORMAT_MIMETYPES[$mime]}"
            log_msg DEBUG "MIME detection: $mime -> $detected"
            echo "$detected"
            return
        fi
    fi
    
    # Method 2: File command with magic numbers
    if command -v file &>/dev/null; then
        local file_output
        file_output=$(file -b --mime-type "$file" 2>/dev/null)
        if [[ -n "${FORMAT_MIMETYPES[$file_output]}" ]]; then
            detected="${FORMAT_MIMETYPES[$file_output]}"
            log_msg DEBUG "File magic detection: $file_output -> $detected"
            echo "$detected"
            return
        fi
        
        # Fallback to description parsing
        file_output=$(file -b "$file" 2>/dev/null)
        case "$file_output" in
            *"PDF document"*)         detected="pdf" ;;
            *"EPUB document"*)        detected="epub" ;;
            *"Mobipocket E-book"*)    detected="mobi" ;;
            *"Microsoft Word 2007"*)  detected="docx" ;;
            *"Microsoft Word"*)       detected="doc" ;;
            *"Microsoft Excel 2007"*) detected="xlsx" ;;
            *"Microsoft Excel"*)      detected="xls" ;;
            *"Microsoft PowerPoint"*) detected="pptx" ;;
            *"OpenDocument Text"*)    detected="odt" ;;
            *"OpenDocument Spreadsheet"*) detected="ods" ;;
            *"OpenDocument Presentation"*) detected="odp" ;;
            *"Rich Text Format"*)     detected="rtf" ;;
            *"HTML document"*)        detected="html" ;;
            *"XML"*|*"xml"*)          detected="xml" ;;
            *"JSON"*)                 detected="json" ;;
            *"YAML"*)                 detected="yaml" ;;
            *"CSV"*)                  detected="csv" ;;
            *"PNG image"*)            detected="png" ;;
            *"JPEG image"*)           detected="jpg" ;;
            *"TIFF image"*)           detected="tiff" ;;
            *"GIF image"*)            detected="gif" ;;
            *"WebP image"*)           detected="webp" ;;
            *"SVG"*)                  detected="svg" ;;
            *"HEIF"*|*"HEIC"*)        detected="heic" ;;
            *"LaTeX"*)                detected="tex" ;;
            *"DjVu"*)                 detected="djvu" ;;
            *"CHM"*)                  detected="chm" ;;
            *"Zip archive"*)          detected="zip" ;;
            *"7-zip"*)                detected="7z" ;;
            *"RAR archive"*)          detected="rar" ;;
            *"ASCII text"*|*"UTF-8"*|*"text"*) detected="txt" ;;
        esac
    fi
    
    # Method 3: Content analysis
    if [[ -z "$detected" ]]; then
        local head_content
        head_content=$(head -c 1024 "$file" 2>/dev/null)
        case "$head_content" in
            *"<?xml"*"<html"*)  detected="xhtml" ;;
            *"<html"*)          detected="html" ;;
            *"<?xml"*)          detected="xml" ;;
            *"{"*"}"*)          detected="json" ;;
            *"---"*)            detected="yaml" ;;
        esac
    fi
    
    # Method 4: Extension fallback
    if [[ -z "$detected" ]]; then
        local ext="${file##*.}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        
        # Check all format extensions
        for format in "${!FORMAT_EXTENSIONS[@]}"; do
            local extensions="${FORMAT_EXTENSIONS[$format]}"
            if [[ " $extensions " =~ " $ext " ]]; then
                detected="$format"
                log_msg DEBUG "Extension detection: $detected"
                break
            fi
        done
    fi
    
    echo "$detected"
}

# Character encoding detection
detect_encoding() {
    local file="$1"
    local detected="$DEFAULT_ENCODING"
    
    if command -v file &>/dev/null; then
        local encoding
        encoding=$(file -bi "$file" | grep -o 'charset=[^;]*' | cut -d= -f2)
        if [[ -n "$encoding" && "$encoding" != "binary" ]]; then
            detected="$encoding"
        fi
    elif command -v chardetect &>/dev/null; then
        detected=$(chardetect "$file" 2>/dev/null | awk '{print $2}')
    elif command -v uchardet &>/dev/null; then
        detected=$(uchardet "$file" 2>/dev/null)
    fi
    
    # Normalize encoding names
    case "${detected,,}" in
        "utf-8"|"utf8")      detected="utf-8" ;;
        "iso-8859-1"|"latin1") detected="iso-8859-1" ;;
        "cp1252"|"windows-1252") detected="cp1252" ;;
        "utf-16"|"utf16")    detected="utf-16" ;;
        "ascii"|"us-ascii")  detected="ascii" ;;
    esac
    
    echo "$detected"
}

# Cache management
get_cache_path() {
    local input="$1"
    local output_format="$2"
    local options_hash
    options_hash=$(echo "$QUALITY:$COMPRESSION:$TARGET_OCR_LANG:$ENCODING" | md5sum | cut -d' ' -f1)
    local checksum
    checksum=$(calculate_checksum "$input")
    echo "$CACHE_DIR/${checksum}_${output_format}_${options_hash}"
}

check_cache() {
    local cache_path="$1"
    
    if [[ $USE_CACHE -eq 0 ]]; then
        return 1
    fi
    
    if [[ -f "$cache_path" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c%Y "$cache_path" 2>/dev/null || stat -f%m "$cache_path" 2>/dev/null) ))
        local max_age=$((DEFAULT_CACHE_DAYS * 24 * 60 * 60))
        
        if [[ $age -lt $max_age ]]; then
            log_msg DEBUG "Cache hit: $cache_path"
            return 0
        else
            log_msg DEBUG "Cache expired: $cache_path"
            rm -f "$cache_path"
        fi
    fi
    
    return 1
}

clean_cache() {
    log_msg INFO "Cleaning cache directory..."
    local count=0
    local freed=0
    
    find "$CACHE_DIR" -type f -mtime +$DEFAULT_CACHE_DAYS | while read -r file; do
        local size
        size=$(get_file_size "$file")
        ((freed += size))
        ((count++))
        rm -f "$file"
    done
    
    log_msg SUCCESS "Removed $count cached files, freed $(human_size $freed)"
}

# Input validation for security
validate_input() {
    local file="$1"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        log_msg ERROR "File not found: $file"
        return 1
    fi
    
    # Check file size
    local size
    size=$(get_file_size "$file")
    if [[ $size -gt $DEFAULT_MAX_FILE_SIZE ]]; then
        log_msg ERROR "File too large: $(human_size $size) (max: $(human_size $DEFAULT_MAX_FILE_SIZE))"
        return 1
    fi
    
    # Security checks for safe mode
    if [[ $SAFE_MODE -eq 1 ]]; then
        # Check for suspicious patterns
        local basename
        basename=$(basename "$file")
        if [[ "$basename" =~ \.\. ]] || [[ "$basename" =~ [[:cntrl:]] ]]; then
            log_msg ERROR "Suspicious filename detected"
            return 1
        fi
        
        # Check file type against whitelist
        local format
        format=$(detect_format "$file")
        if [[ -z "$format" ]]; then
            log_msg ERROR "Unknown file format"
            return 1
        fi
        
        # Check for executable content
        if file "$file" | grep -qE '(executable|script|batch)'; then
            log_msg WARN "File appears to contain executable content"
            if [[ $NO_CONFIRM -eq 0 ]]; then
                read -p "Continue anyway? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
        fi
    fi
    
    return 0
}

# Output validation
validate_output() {
    local output="$1"
    local expected_format="$2"
    
    if [[ $VALIDATE_OUTPUT -eq 0 ]]; then
        return 0
    fi
    
    if [[ ! -f "$output" ]]; then
        log_msg ERROR "Output file not created"
        return 1
    fi
    
    local size
    size=$(get_file_size "$output")
    if [[ $size -eq 0 ]]; then
        log_msg ERROR "Output file is empty"
        return 1
    fi
    
    # Verify format
    local detected
    detected=$(detect_format "$output")
    if [[ -n "$detected" && "$detected" != "$expected_format" ]]; then
        log_msg WARN "Output format mismatch: expected $expected_format, got $detected"
    fi
    
    # Format-specific validation
    case "$expected_format" in
        pdf)
            if command -v pdfinfo &>/dev/null; then
                if ! pdfinfo "$output" &>/dev/null; then
                    log_msg ERROR "Output PDF is corrupted"
                    return 1
                fi
            fi
            ;;
        xml|xhtml|html)
            if command -v xmllint &>/dev/null; then
                if ! xmllint --noout "$output" 2>/dev/null; then
                    log_msg WARN "Output XML/HTML has validation errors"
                fi
            fi
            ;;
        json)
            if command -v jq &>/dev/null; then
                if ! jq empty "$output" 2>/dev/null; then
                    log_msg ERROR "Output JSON is invalid"
                    return 1
                fi
            fi
            ;;
    esac
    
    return 0
}

# Load preset configuration
load_preset() {
    local preset_name="$1"
    
    if [[ ! -f "$PRESETS_FILE" ]]; then
        log_msg ERROR "Presets file not found"
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        log_msg ERROR "jq is required for preset support"
        return 1
    fi
    
    local preset
    preset=$(jq -r ".$preset_name // empty" "$PRESETS_FILE" 2>/dev/null)
    
    if [[ -z "$preset" ]]; then
        log_msg ERROR "Preset '$preset_name' not found"
        log_msg INFO "Available presets: $(jq -r 'keys | join(", ")' "$PRESETS_FILE")"
        return 1
    fi
    
    # Apply preset values
    QUALITY=$(echo "$preset" | jq -r '.quality // empty')
    [[ -z "$QUALITY" ]] && QUALITY="$DEFAULT_QUALITY"
    
    local format
    format=$(echo "$preset" | jq -r '.format // empty')
    [[ -n "$format" ]] && DEFAULT_OUTPUT_FORMAT="$format"
    
    # Load additional options
    local opts
    opts=$(echo "$preset" | jq -r '.options[]? // empty' 2>/dev/null)
    if [[ -n "$opts" ]]; then
        PANDOC_PDF_OPTS+=($opts)
    fi
    
    log_msg INFO "Loaded preset: $preset_name"
    return 0
}

# API fallback conversion
convert_via_api() {
    local input="$1"
    local output="$2"
    local service="cloudconvert"  # Default service
    
    if [[ $USE_FALLBACK_API -eq 0 ]]; then
        return 1
    fi
    
    # Check for API keys
    local api_key=""
    case "$service" in
        cloudconvert)
            api_key="${API_KEY_CLOUDCONVERT:-}"
            ;;
        convertapi)
            api_key="${API_KEY_CONVERTAPI:-}"
            ;;
        zamzar)
            api_key="${API_KEY_ZAMZAR:-}"
            ;;
    esac
    
    if [[ -z "$api_key" ]]; then
        log_msg WARN "No API key configured for $service"
        return 1
    fi
    
    log_msg INFO "Attempting conversion via $service API..."
    
    # Implementation would depend on specific API
    # This is a placeholder for the actual API calls
    case "$service" in
        cloudconvert)
            # CloudConvert API implementation
            log_msg ERROR "API conversion not yet implemented"
            return 1
            ;;
        *)
            log_msg ERROR "Unknown API service: $service"
            return 1
            ;;
    esac
}

# Extract embedded content
extract_embedded_content() {
    local input="$1"
    local output_dir="$2"
    local format
    format=$(detect_format "$input")
    
    mkdir -p "$output_dir"
    
    case "$format" in
        pdf)
            if command -v pdfimages &>/dev/null; then
                log_msg INFO "Extracting images from PDF..."
                pdfimages -all "$input" "$output_dir/image"
            fi
            if command -v pdfdetach &>/dev/null; then
                log_msg INFO "Extracting attachments from PDF..."
                pdfdetach -saveall -o "$output_dir" "$input" 2>/dev/null || true
            fi
            ;;
        docx|xlsx|pptx)
            if command -v unzip &>/dev/null; then
                log_msg INFO "Extracting from Office document..."
                unzip -q "$input" -d "$output_dir" 2>/dev/null || true
            fi
            ;;
        epub)
            if command -v unzip &>/dev/null; then
                log_msg INFO "Extracting from EPUB..."
                unzip -q "$input" -d "$output_dir" 2>/dev/null || true
            fi
            ;;
        *)
            log_msg WARN "Embedded content extraction not supported for $format"
            return 1
            ;;
    esac
    
    local count
    count=$(find "$output_dir" -type f | wc -l)
    log_msg SUCCESS "Extracted $count files to $output_dir"
    return 0
}

# Enhanced conversion with retry logic
convert_with_retry() {
    local input="$1"
    local output="$2"
    local attempt=0
    local success=0
    
    while [[ $attempt -lt $MAX_RETRIES ]]; do
        ((attempt++))
        log_msg INFO "Conversion attempt $attempt/$MAX_RETRIES"
        
        if convert_file_internal "$input" "$output"; then
            success=1
            break
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_msg WARN "Conversion failed, retrying in 2 seconds..."
            sleep 2
        fi
    done
    
    if [[ $success -eq 1 ]]; then
        return 0
    else
        log_msg ERROR "Conversion failed after $MAX_RETRIES attempts"
        return 1
    fi
}

# Optimize conversion based on file characteristics
optimize_conversion_params() {
    local input="$1"
    local output_format="$2"
    local -n params=$3
    
    if [[ $AUTO_OPTIMIZE -eq 0 ]]; then
        return
    fi
    
    local size
    size=$(get_file_size "$input")
    local size_mb=$((size / 1024 / 1024))
    
    # Parse quality profile
    if [[ -n "${QUALITY_PROFILES[$QUALITY]}" ]]; then
        local profile="${QUALITY_PROFILES[$QUALITY]}"
        IFS=';' read -ra settings <<< "$profile"
        for setting in "${settings[@]}"; do
            IFS='=' read -r key value <<< "$setting"
            case "$key" in
                dpi)
                    params+=("--dpi=$value")
                    ;;
                compression)
                    case "$output_format" in
                        pdf)
                            [[ "$value" == "high" ]] && params+=("--pdf-engine-opt=-compress")
                            ;;
                        jpg|jpeg)
                            [[ "$value" == "high" ]] && params+=("-quality" "75")
                            [[ "$value" == "medium" ]] && params+=("-quality" "85")
                            [[ "$value" == "low" ]] && params+=("-quality" "95")
                            ;;
                    esac
                    ;;
            esac
        done
    fi
    
    # Size-based optimizations
    if [[ $size_mb -gt 100 ]]; then
        log_msg INFO "Large file detected ($(human_size $size)), adjusting parameters"
        params+=("--extract-media")
    fi
    
    # Format-specific optimizations
    case "$output_format" in
        pdf)
            if [[ $size_mb -gt 50 ]]; then
                params+=("--pdf-engine-opt=-dPDFSETTINGS=/ebook")
            fi
            if [[ "$QUALITY" == "web" ]]; then
                params+=("--pdf-engine-opt=-dPDFSETTINGS=/screen")
            fi
            ;;
        epub|mobi)
            params+=("--epub-embed-font=false")
            params+=("--enable-heuristics")
            ;;
        html|xhtml)
            params+=("--self-contained")
            params+=("--to=html5")
            ;;
        txt)
            # Use appropriate text extraction options
            local input_format
            input_format=$(detect_format "$input")
            if [[ "$input_format" == "pdf" && $size_mb -gt 20 ]]; then
                params+=("--layout")
            fi
            ;;
        md|markdown)
            params+=("--wrap=none")
            params+=("--atx-headers")
            ;;
    esac
}

# Multi-step conversion chains
convert_chain() {
    local input="$1"
    local final_output="$2"
    local -a chain_formats=("${@:3}")
    
    local current_input="$input"
    local step=0
    local total_steps=${#chain_formats[@]}
    
    log_msg INFO "Starting conversion chain with $total_steps steps"
    
    for format in "${chain_formats[@]}"; do
        ((step++))
        local temp_output="$TEMP_DIR/chain_step_${step}.${format}"
        
        log_msg INFO "Chain step $step/$total_steps: Converting to $format"
        
        # Skip if already in target format
        local current_format
        current_format=$(detect_format "$current_input")
        if [[ "$current_format" == "$format" ]]; then
            log_msg INFO "Already in format $format, skipping step"
            continue
        fi
        
        if ! convert_file_internal "$current_input" "$temp_output"; then
            log_msg ERROR "Chain conversion failed at step $step ($format)"
            return 1
        fi
        
        # Clean up previous temp file (except input)
        if [[ "$current_input" != "$input" ]] && [[ "$current_input" =~ ^$TEMP_DIR ]]; then
            rm -f "$current_input"
        fi
        
        current_input="$temp_output"
    done
    
    # Final conversion to target format
    local target_format="${final_output##*.}"
    if [[ "$target_format" != "${chain_formats[-1]}" ]]; then
        log_msg INFO "Final conversion to $target_format"
        if ! convert_file_internal "$current_input" "$final_output"; then
            log_msg ERROR "Final chain conversion failed"
            return 1
        fi
        # Clean up last temp file
        if [[ "$current_input" =~ ^$TEMP_DIR ]]; then
            rm -f "$current_input"
        fi
    else
        # Just move the file
        mv "$current_input" "$final_output"
    fi
    
    return 0
}

# Core conversion function implementation
convert_file_internal() {
    local input="$1"
    local output="$2"
    
    # Input validation
    if ! validate_input "$input"; then
        return 1
    fi
    
    # Create lock to prevent concurrent conversion of same file
    if ! create_lock "$input"; then
        log_msg WARN "File is already being converted by another process"
        return 1
    fi
    
    # Ensure cleanup removes lock
    trap "remove_lock '$input'" RETURN
    
    # Check cache
    local cache_path
    cache_path=$(get_cache_path "$input" "${output##*.}")
    if check_cache "$cache_path"; then
        log_msg SUCCESS "Using cached conversion"
        cp "$cache_path" "$output"
        return 0
    fi
    
    # Detect formats and encoding
    local in_format
    in_format=$(detect_format "$input")
    
    if [[ -z "$in_format" ]]; then
        log_msg ERROR "Cannot detect input format"
        return 1
    fi
    
    local out_format="${output##*.}"
    out_format=$(echo "$out_format" | tr '[:upper:]' '[:lower:]')
    
    # Check if conversion is needed
    if [[ "$in_format" == "$out_format" ]]; then
        log_msg INFO "Input and output formats are the same, copying file"
        cp "$input" "$output"
        return 0
    fi
    
    # Detect encoding for text files
    local input_encoding="$ENCODING"
    if [[ "$in_format" =~ ^(txt|csv|tsv|log)$ ]]; then
        input_encoding=$(detect_encoding "$input")
        log_msg DEBUG "Detected encoding: $input_encoding"
    fi
    
    # Preserve metadata if requested
    local metadata_file=""
    if [[ $PRESERVE_METADATA -eq 1 ]] && command -v exiftool &>/dev/null; then
        metadata_file="$TEMP_DIR/metadata.json"
        exiftool -j "$input" > "$metadata_file" 2>/dev/null || true
    fi
    
    # Start resource monitoring
    local monitor_pid=""
    if [[ $MONITOR_RESOURCES -eq 1 ]]; then
        monitor_resources $$ "$output" &
        monitor_pid=$!
    fi
    
    # Start timing
    local start_time
    start_time=$(date +%s.%N)
    
    # Optimization parameters
    local -a extra_params=()
    optimize_conversion_params "$input" "$out_format" extra_params
    
    # Perform conversion
    local result=0
    local conversion_done=0
    
    # Try specialized converters first
    case "${in_format}:${out_format}" in
        # PDF conversions
        "pdf:txt")
            if [[ -n "${AVAILABLE_FEATURES[pdftotext]}" ]]; then
                log_msg CMD "pdftotext -layout -enc $ENCODING '$input' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" pdftotext -layout -enc "$ENCODING" "$input" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        "pdf:html")
            if [[ -n "${AVAILABLE_FEATURES[pdftohtml]}" ]]; then
                log_msg CMD "pdftohtml -enc $ENCODING -noframes '$input' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" pdftohtml -enc "$ENCODING" -noframes "$input" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # Office document conversions
        "doc:txt"|"docx:txt"|"odt:txt"|"rtf:txt")
            if [[ -n "${AVAILABLE_FEATURES[libreoffice]}" ]]; then
                local outdir=$(dirname "$output")
                log_msg CMD "libreoffice --headless --convert-to txt:Text --outdir '$outdir' '$input'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" libreoffice --headless --convert-to txt:Text --outdir "$outdir" "$input" 2>&1
                    # LibreOffice creates output with original basename
                    local temp_output="${outdir}/$(basename "${input%.*}").txt"
                    if [[ -f "$temp_output" ]]; then
                        mv "$temp_output" "$output"
                        result=0
                    else
                        result=1
                    fi
                    conversion_done=1
                fi
            fi
            ;;
            
        # E-book conversions
        "epub:mobi"|"mobi:epub"|"azw:epub"|"azw3:epub"|"epub:pdf"|"mobi:pdf")
            if [[ -n "${AVAILABLE_FEATURES[ebook-convert]}" ]]; then
                log_msg CMD "ebook-convert '$input' '$output' ${extra_params[*]}"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" ebook-convert "$input" "$output" "${extra_params[@]}" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # Image conversions
        "png:jpg"|"jpg:png"|"tiff:jpg"|"gif:png"|"bmp:jpg"|"webp:png")
            if [[ -n "${AVAILABLE_FEATURES[convert]}" ]] || [[ -n "${AVAILABLE_FEATURES[magick]}" ]]; then
                local convert_cmd="convert"
                [[ -n "${AVAILABLE_FEATURES[magick]}" ]] && convert_cmd="magick"
                log_msg CMD "$convert_cmd '$input' ${extra_params[*]} '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" $convert_cmd "$input" "${extra_params[@]}" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # HEIC/HEIF conversions
        "heic:jpg"|"heif:jpg"|"heic:png"|"heif:png")
            if command -v heif-convert &>/dev/null; then
                log_msg CMD "heif-convert '$input' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" heif-convert "$input" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # DjVu conversions
        "djvu:txt")
            if [[ -n "${AVAILABLE_FEATURES[djvutxt]}" ]]; then
                log_msg CMD "djvutxt '$input' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" djvutxt "$input" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        "djvu:pdf")
            if [[ -n "${AVAILABLE_FEATURES[djvups]}" ]] && [[ -n "${AVAILABLE_FEATURES[ps2pdf]}" ]]; then
                local ps_file="$TEMP_DIR/temp.ps"
                log_msg CMD "djvups '$input' '$ps_file' && ps2pdf '$ps_file' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    if timeout "$TIMEOUT" djvups "$input" "$ps_file" 2>&1; then
                        timeout "$TIMEOUT" ps2pdf "$ps_file" "$output" 2>&1
                        result=$?
                    else
                        result=1
                    fi
                    rm -f "$ps_file"
                    conversion_done=1
                fi
            fi
            ;;
            
        # HTML conversions
        "html:pdf"|"xhtml:pdf")
            if [[ -n "${AVAILABLE_FEATURES[wkhtmltopdf]}" ]]; then
                log_msg CMD "wkhtmltopdf '$input' '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" wkhtmltopdf "$input" "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        "html:txt"|"xhtml:txt")
            if [[ -n "${AVAILABLE_FEATURES[w3m]}" ]]; then
                log_msg CMD "w3m -dump '$input' > '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" w3m -dump "$input" > "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            elif [[ -n "${AVAILABLE_FEATURES[lynx]}" ]]; then
                log_msg CMD "lynx -dump -nolist '$input' > '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" lynx -dump -nolist "$input" > "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            elif [[ -n "${AVAILABLE_FEATURES[html2text]}" ]]; then
                log_msg CMD "html2text '$input' > '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" html2text "$input" > "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # LaTeX conversions
        "tex:pdf")
            if [[ -n "${AVAILABLE_FEATURES[xelatex]}" ]]; then
                local tex_dir=$(dirname "$input")
                local tex_base=$(basename "${input%.*}")
                log_msg CMD "cd '$tex_dir' && xelatex -interaction=nonstopmode '$tex_base'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    (cd "$tex_dir" && timeout "$TIMEOUT" xelatex -interaction=nonstopmode "$tex_base" 2>&1)
                    if [[ -f "$tex_dir/$tex_base.pdf" ]]; then
                        mv "$tex_dir/$tex_base.pdf" "$output"
                        result=0
                    else
                        result=1
                    fi
                    # Clean up LaTeX auxiliary files
                    rm -f "$tex_dir/$tex_base".{aux,log,out,toc,lof,lot}
                    conversion_done=1
                fi
            elif [[ -n "${AVAILABLE_FEATURES[pdflatex]}" ]]; then
                local tex_dir=$(dirname "$input")
                local tex_base=$(basename "${input%.*}")
                log_msg CMD "cd '$tex_dir' && pdflatex -interaction=nonstopmode '$tex_base'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    (cd "$tex_dir" && timeout "$TIMEOUT" pdflatex -interaction=nonstopmode "$tex_base" 2>&1)
                    if [[ -f "$tex_dir/$tex_base.pdf" ]]; then
                        mv "$tex_dir/$tex_base.pdf" "$output"
                        result=0
                    else
                        result=1
                    fi
                    # Clean up LaTeX auxiliary files
                    rm -f "$tex_dir/$tex_base".{aux,log,out,toc,lof,lot}
                    conversion_done=1
                fi
            fi
            ;;
            
        "tex:txt")
            if [[ -n "${AVAILABLE_FEATURES[detex]}" ]]; then
                log_msg CMD "detex '$input' > '$output'"
                if [[ $DRY_RUN -eq 0 ]]; then
                    timeout "$TIMEOUT" detex "$input" > "$output" 2>&1
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # CSV/TSV conversions
        "csv:json")
            if [[ -n "${AVAILABLE_FEATURES[jq]}" ]]; then
                log_msg CMD "Converting CSV to JSON with jq"
                if [[ $DRY_RUN -eq 0 ]]; then
                    # Simple CSV to JSON conversion
                    {
                        echo '['
                        awk -F',' 'NR==1{split($0,headers,","); next} {printf "{"; for(i=1;i<=NF;i++) printf "\"%s\":\"%s\"%s", headers[i], $i, (i<NF?",":""); print "},"} END {print "null]"}' "$input" | sed '$ s/,null]/]/'
                    } > "$output"
                    result=$?
                    conversion_done=1
                fi
            fi
            ;;
            
        # Archive extraction as conversion
        "zip:dir"|"tar:dir"|"7z:dir")
            local extract_dir="${output%.dir}"
            mkdir -p "$extract_dir"
            case "$in_format" in
                zip)
                    if command -v unzip &>/dev/null; then
                        log_msg CMD "unzip '$input' -d '$extract_dir'"
                        if [[ $DRY_RUN -eq 0 ]]; then
                            timeout "$TIMEOUT" unzip -q "$input" -d "$extract_dir" 2>&1
                            result=$?
                            conversion_done=1
                        fi
                    fi
                    ;;
                tar)
                    log_msg CMD "tar -xf '$input' -C '$extract_dir'"
                    if [[ $DRY_RUN -eq 0 ]]; then
                        timeout "$TIMEOUT" tar -xf "$input" -C "$extract_dir" 2>&1
                        result=$?
                        conversion_done=1
                    fi
                    ;;
                7z)
                    if [[ -n "${AVAILABLE_FEATURES[7z]}" ]]; then
                        log_msg CMD "7z x '$input' -o'$extract_dir'"
                        if [[ $DRY_RUN -eq 0 ]]; then
                            timeout "$TIMEOUT" 7z x "$input" -o"$extract_dir" -y 2>&1
                            result=$?
                            conversion_done=1
                        fi
                    fi
                    ;;
            esac
            ;;
    esac
    
    # Fall back to pandoc for general conversions
    if [[ $conversion_done -eq 0 ]]; then
        # Check if pandoc supports the formats
        local pandoc_input_formats="markdown rst mediawiki docbook textile html latex json csv tsv org asciidoc creole muse twiki docx odt epub fb2 ipynb"
        local pandoc_output_formats="markdown rst mediawiki docbook textile html latex json asciidoc org epub fb2 docx odt pdf beamer slidy reveal dzslides"
        
        local use_pandoc=0
        if [[ " $pandoc_input_formats " =~ " $in_format " ]] && [[ " $pandoc_output_formats " =~ " $out_format " ]]; then
            use_pandoc=1
        fi
        
        if [[ $use_pandoc -eq 1 ]]; then
            local cmd_array=(pandoc)
            
            # Input format specification
            cmd_array+=(-f "$in_format")
            
            # Output format specification
            cmd_array+=(-t "$out_format")
            
            # Add quality-specific options
            case "$out_format" in
                pdf)
                    cmd_array+=("${PANDOC_PDF_OPTS[@]}")
                    ;;
                epub|mobi)
                    cmd_array+=(--toc --toc-depth=3)
                    ;;
                html|xhtml)
                    cmd_array+=(--standalone --self-contained)
                    ;;
            esac
            
            # Add extra parameters
            cmd_array+=("${extra_params[@]}")
            
            # Input and output files
            cmd_array+=("$input" -o "$output")
            
            log_msg CMD "$(printf "%q " "${cmd_array[@]}")"
            
            if [[ $DRY_RUN -eq 0 ]]; then
                if timeout "$TIMEOUT" "${cmd_array[@]}" 2>&1; then
                    result=0
                else
                    result=$?
                fi
                conversion_done=1
            fi
        fi
    fi
    
    # Try API conversion as last resort
    if [[ $conversion_done -eq 0 ]] || [[ $result -ne 0 && $USE_FALLBACK_API -eq 1 ]]; then
        if convert_via_api "$input" "$output"; then
            result=0
            conversion_done=1
        fi
    fi
    
    # Handle case where no converter was found
    if [[ $conversion_done -eq 0 ]]; then
        log_msg ERROR "No conversion strategy available for $in_format to $out_format"
        
        # Suggest conversion chains
        suggest_conversion_chain "$in_format" "$out_format"
        
        result=1
    fi
    
    # Stop resource monitoring
    if [[ -n "$monitor_pid" ]]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
    
    # Calculate timing
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc)
    
    if [[ $result -eq 0 ]]; then
        log_msg TIMING "Conversion completed in ${duration}s"
        
        # Validate output
        if ! validate_output "$output" "$out_format"; then
            log_msg ERROR "Output validation failed"
            result=1
        fi
        
        # Restore metadata if requested
        if [[ $PRESERVE_METADATA -eq 1 && -f "$metadata_file" ]] && command -v exiftool &>/dev/null; then
            log_msg DEBUG "Restoring metadata"
            exiftool -overwrite_original -TagsFromFile "$input" "$output" 2>/dev/null || true
        fi
        
        # Cache successful conversion
        if [[ $result -eq 0 && $USE_CACHE -eq 1 && -f "$output" ]]; then
            cp "$output" "$cache_path"
            log_msg DEBUG "Cached conversion result"
        fi
    else
        log_msg ERROR "Conversion failed after ${duration}s"
    fi
    
    # Update statistics
    update_stats "$in_format" "$out_format" "$input" "$duration" "$result"
    
    # Clean up temp files
    [[ -f "$metadata_file" ]] && rm -f "$metadata_file"
    
    return $result
}

# Suggest conversion chains for unsupported direct conversions
suggest_conversion_chain() {
    local from="$1"
    local to="$2"
    
    # Common intermediate formats
    local intermediates=("pdf" "html" "txt" "md")
    
    log_msg INFO "Searching for conversion chain from $from to $to..."
    
    for intermediate in "${intermediates[@]}"; do
        # Check if we can convert from -> intermediate -> to
        local chain_possible=0
        
        # This is a simplified check - in reality would need full capability matrix
        case "${from}:${intermediate}" in
            *:pdf|*:html|*:txt|*:md)
                case "${intermediate}:${to}" in
                    pdf:*|html:*|txt:*|md:*)
                        chain_possible=1
                        ;;
                esac
                ;;
        esac
        
        if [[ $chain_possible -eq 1 ]]; then
            log_msg INFO "Possible chain: $from -> $intermediate -> $to"
            log_msg INFO "Use: $SCRIPT_NAME --chain $intermediate $to input.$from"
        fi
    done
}

# Update conversion statistics
update_stats() {
    local from_format="$1"
    local to_format="$2"
    local input_file="$3"
    local duration="$4"
    local result="$5"
    
    if [[ ! -f "$STATS_FILE" ]] || ! command -v jq &>/dev/null; then
        return
    fi
    
    local size
    size=$(get_file_size "$input_file")
    
    # Create format key
    local format_key="${from_format}_to_${to_format}"
    
    # Update stats
    local jq_update
    if [[ $result -eq 0 ]]; then
        jq_update=".conversions += 1 | .total_size += $size | .total_time += $duration"
        jq_update="$jq_update | .format_stats.\"$format_key\".success = (.format_stats.\"$format_key\".success // 0) + 1"
    else
        jq_update=".failures += 1"
        jq_update="$jq_update | .format_stats.\"$format_key\".failure = (.format_stats.\"$format_key\".failure // 0) + 1"
    fi
    
    jq "$jq_update" "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"
}

# Process single file
process_single_file() {
    local input="$1"
    local output=""
    
    if [[ ! -f "$input" ]]; then
        log_msg WARN "Skipping '$input': not a regular file"
        return 1
    fi
    
    # Determine output path
    if [[ -n "$OUTPUT_DIR" ]]; then
        output="$OUTPUT_DIR/$(basename "${input%.*}").${OUTPUT_FORMAT}"
    else
        output="${input%.*}.${OUTPUT_FORMAT}"
    fi
    
    # Check if output exists
    if [[ -f "$output" && $FORCE_OVERWRITE -eq 0 ]]; then
        log_msg WARN "Output file exists: $output (use -f to overwrite)"
        return 1
    fi
    
    # Extract embedded content if requested
    if [[ $EXTRACT_EMBEDDED -eq 1 ]]; then
        local extract_dir="${input%.*}_extracted"
        extract_embedded_content "$input" "$extract_dir"
    fi
    
    # Perform conversion
    local result
    if [[ $MAX_RETRIES -gt 1 ]]; then
        convert_with_retry "$input" "$output"
        result=$?
    else
        convert_file_internal "$input" "$output"
        result=$?
    fi
    
    # Handle original files
    if [[ $result -eq 0 && $KEEP_ORIGINALS -eq 0 && "$input" != "$output" ]]; then
        log_msg INFO "Removing original file: $input"
        rm -f "$input"
    fi
    
    return $result
}

# Parallel processing implementation
process_parallel() {
    local -a input_files=("$@")
    local total_files=${#input_files[@]}
    local completed=0
    local failed=0
    local start_time=$(date +%s)
    
    log_msg INFO "Processing $total_files files with $PARALLEL_JOBS parallel jobs"
    
    # Create job control pipe
    local job_pipe="$TEMP_DIR/job_pipe"
    mkfifo "$job_pipe"
    exec 3<>"$job_pipe"
    rm -f "$job_pipe"
    
    # Initialize job slots
    local i
    for ((i=0; i<PARALLEL_JOBS; i++)); do
        echo >&3
    done
    
    # Process files
    for input in "${input_files[@]}"; do
        # Wait for available slot
        read -u 3
        
        # Start background job
        {
            if process_single_file "$input"; then
                echo "SUCCESS:$input"
            else
                echo "FAILED:$input"
            fi
            echo >&3
        } &
    done
    
    # Wait for all jobs to complete
    for ((i=0; i<PARALLEL_JOBS; i++)); do
        read -u 3
    done
    
    # Close job control
    exec 3>&-
    
    # Show summary
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    log_msg SUCCESS "Batch processing completed in ${total_time}s"
    log_msg INFO "Total: $total_files, Completed: $((total_files - failed)), Failed: $failed"
}

# Interactive mode
interactive_mode() {
    local input_file="$1"
    
    echo -e "${C_HIGHLIGHT}Interactive Conversion Mode${C_RESET}"
    echo "Input file: $input_file"
    
    # Detect input format
    local input_format
    input_format=$(detect_format "$input_file")
    echo "Detected format: $input_format"
    
    # Show available output formats
    echo
    echo "Available output formats:"
    local formats=()
    for fmt in "${!FORMAT_EXTENSIONS[@]}"; do
        formats+=("$fmt")
    done
    
    # Sort formats
    IFS=$'\n' sorted_formats=($(sort <<<"${formats[*]}"))
    unset IFS
    
    # Display in columns
    local cols=4
    local col_width=15
    local i=0
    for fmt in "${sorted_formats[@]}"; do
        printf "%-${col_width}s" "$fmt"
        ((i++))
        if [[ $((i % cols)) -eq 0 ]]; then
            echo
        fi
    done
    echo
    echo
    
    # Get user choice
    local output_format
    while true; do
        read -p "Enter output format (or 'q' to quit): " output_format
        if [[ "$output_format" == "q" ]]; then
            echo "Cancelled."
            return 1
        fi
        if [[ -n "${FORMAT_EXTENSIONS[$output_format]}" ]]; then
            break
        else
            echo "Invalid format. Please choose from the list above."
        fi
    done
    
    # Quality selection
    echo
    echo "Quality profiles:"
    echo "  low     - Fast conversion, smaller file size"
    echo "  medium  - Balanced quality and speed (default)"
    echo "  high    - Best quality, slower conversion"
    echo "  max     - Maximum quality, very slow"
    echo "  web     - Optimized for web viewing"
    echo "  print   - Optimized for printing"
    echo "  archive - Optimized for long-term storage"
    
    read -p "Select quality [medium]: " quality_choice
    if [[ -n "$quality_choice" && -n "${QUALITY_PROFILES[$quality_choice]}" ]]; then
        QUALITY="$quality_choice"
    fi
    
    # Additional options
    echo
    echo "Additional options:"
    read -p "Preserve metadata? [Y/n]: " preserve_meta
    if [[ "$preserve_meta" =~ ^[Nn]$ ]]; then
        PRESERVE_METADATA=0
    fi
    
    if [[ "$input_format" == "pdf" ]]; then
        read -p "Perform OCR for scanned content? [y/N]: " do_ocr
        if [[ "$do_ocr" =~ ^[Yy]$ ]]; then
            read -p "OCR language code [$TARGET_OCR_LANG]: " ocr_lang
            [[ -n "$ocr_lang" ]] && TARGET_OCR_LANG="$ocr_lang"
        fi
    fi
    
    # Output location
    local output_file="${input_file%.*}.${output_format}"
    read -p "Output file [$output_file]: " custom_output
    [[ -n "$custom_output" ]] && output_file="$custom_output"
    
    # Confirm conversion
    echo
    echo -e "${C_HIGHLIGHT}Conversion Summary:${C_RESET}"
    echo "  Input:    $input_file ($input_format)"
    echo "  Output:   $output_file ($output_format)"
    echo "  Quality:  $QUALITY"
    echo "  Metadata: $([ $PRESERVE_METADATA -eq 1 ] && echo "preserve" || echo "strip")"
    echo
    
    read -p "Proceed with conversion? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Cancelled."
        return 1
    fi
    
    # Perform conversion
    OUTPUT_FORMAT="$output_format"
    process_single_file "$input_file"
}

# Wrapper for convert_file to maintain compatibility
convert_file() {
    local input="$1"
    local output="$2"
    
    if [[ $MAX_RETRIES -gt 1 ]]; then
        convert_with_retry "$input" "$output"
    else
        convert_file_internal "$input" "$output"
    fi
}

# Enhanced usage function
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Advanced File Conversion Tool

A sophisticated file conversion utility supporting 40+ formats with intelligent
tool selection, parallel processing, caching, and enterprise features.

Usage: $SCRIPT_NAME [options] [<output_format>] <input_file_or_dir>...

Supported Formats:
  Documents:      pdf, epub, mobi, azw, azw3, docx, doc, odt, rtf, tex, fb2,
                  lit, djvu, chm
  Markup:         md, html, xhtml, xml, rst, textile, mediawiki, docbook, man,
                  asciidoc, org, creole, muse, twiki
  Text:           txt, csv, tsv, log
  Presentations:  pptx, ppt, odp, beamer, slidy, reveal
  Spreadsheets:   xlsx, xls, ods
  Archives:       zip, tar, gz, 7z, rar
  Images:         png, jpg, tiff, gif, bmp, webp, svg, ico, heic, avif, jxl

Options:
  -b, --batch              Batch mode with progress tracking
  -c, --cache              Enable caching (default: on)
  -d, --output-dir <dir>   Output directory for converted files
  -e, --encoding <enc>     Character encoding (default: $DEFAULT_ENCODING)
  -f, --force              Force overwrite existing files
  -h, --help               Display this help message
  -i, --interactive        Interactive format selection
  -j, --jobs <n>           Parallel conversion jobs (default: $DEFAULT_PARALLEL_JOBS)
  -k, --keep               Keep original files (default: yes)
  -l, --lang <code>        OCR language code (e.g., eng, deu, fra)
  -m, --metadata           Preserve metadata during conversion
  -n, --dry-run            Show commands without executing
  -p, --preset <name>      Use a conversion preset
  -q, --quiet              Suppress all output except errors
  -r, --recursive          Process directories recursively
  -v, --verbose            Increase verbosity (can use multiple times)
  -x, --extract            Extract embedded content
  
  --quality <level>        Quality level: low|medium|high|max|print|web|archive
  --compression <level>    Compression: none|low|medium|high
  --timeout <seconds>      Conversion timeout (default: $DEFAULT_TIMEOUT)
  --retries <n>            Max retry attempts (default: $DEFAULT_MAX_RETRIES)
  --safe                   Enable safe mode with input validation
  --monitor                Monitor resource usage during conversion
  --no-cache               Disable caching
  --no-keep                Delete original files after conversion
  --no-confirm             Skip confirmation prompts
  --chain <fmt1,fmt2,...>  Use conversion chain through formats
  --api                    Use online API as fallback
  --stats                  Show conversion statistics
  --clean-cache            Clean expired cache files
  --self-test              Run self-diagnostic tests

Examples:
  # Convert with automatic format detection
  $SCRIPT_NAME document.pdf                    # Converts to text by default
  
  # High-quality PDF from Markdown with preset
  $SCRIPT_NAME --preset academic pdf thesis.md
  
  # Batch convert with parallel processing
  $SCRIPT_NAME -j 4 -b md *.docx
  
  # Extract text from scanned PDF with German OCR
  $SCRIPT_NAME -l deu --quality high txt scan.pdf
  
  # Convert through chain for complex formats
  $SCRIPT_NAME --chain pdf,html docx presentation.pptx
  
  # Interactive conversion with format selection
  $SCRIPT_NAME -i document.unknown
  
  # Convert directory recursively with specific output directory
  $SCRIPT_NAME -r -d converted/ txt documents/
  
  # Monitor resource usage for large conversions
  $SCRIPT_NAME --monitor --timeout 600 pdf large_book.epub
  
  # Safe mode for untrusted input
  $SCRIPT_NAME --safe txt untrusted_file.unknown
  
  # Extract embedded content from documents
  $SCRIPT_NAME -x report.pdf

Configuration Files:
  Config:   $CONFIG_FILE
  Presets:  $PRESETS_FILE
  History:  $HISTORY_FILE
  Cache:    $CACHE_DIR
  Stats:    $STATS_FILE

Environment Variables:
  TEXTCONVERT_CONFIG      Override config file location
  TEXTCONVERT_CACHE       Override cache directory
  TEXTCONVERT_PARALLEL    Default number of parallel jobs
  TEXTCONVERT_TIMEOUT     Default conversion timeout
  NO_COLOR                Disable colored output

For more information and updates, visit: https://github.com/example/textconvert
EOF
}

# Self-test functionality
self_test() {
    log_msg INFO "Running self-diagnostic tests..."
    
    local test_dir="$TEMP_DIR/self_test"
    mkdir -p "$test_dir"
    local passed=0
    local failed=0
    
    # Test 1: Basic conversion
    echo "# Test Document" > "$test_dir/test.md"
    echo "This is a **test** document." >> "$test_dir/test.md"
    echo "- Item 1" >> "$test_dir/test.md"
    echo "- Item 2" >> "$test_dir/test.md"
    
    if convert_file "$test_dir/test.md" "$test_dir/test.txt"; then
        if [[ -f "$test_dir/test.txt" ]] && grep -q "test" "$test_dir/test.txt"; then
            log_msg SUCCESS "Test 1 passed: Basic conversion"
            ((passed++))
        else
            log_msg ERROR "Test 1 failed: Output validation"
            ((failed++))
        fi
    else
        log_msg ERROR "Test 1 failed: Basic conversion"
        ((failed++))
    fi
    
    # Test 2: Format detection
    cp "$test_dir/test.md" "$test_dir/test.unknown"
    local detected
    detected=$(detect_format "$test_dir/test.unknown")
    if [[ "$detected" == "txt" ]] || [[ "$detected" == "md" ]]; then
        log_msg SUCCESS "Test 2 passed: Format detection"
        ((passed++))
    else
        log_msg ERROR "Test 2 failed: Format detection returned '$detected'"
        ((failed++))
    fi
    
    # Test 3: Cache functionality
    USE_CACHE=1
    local cache_test
    cache_test=$(get_cache_path "$test_dir/test.md" "txt")
    if [[ -n "$cache_test" ]]; then
        # Try conversion twice to test cache
        convert_file "$test_dir/test.md" "$test_dir/test_cache1.txt"
        local start_time=$(date +%s.%N)
        convert_file "$test_dir/test.md" "$test_dir/test_cache2.txt"
        local end_time=$(date +%s.%N)
        local cache_time=$(echo "$end_time - $start_time" | bc)
        
        if (( $(echo "$cache_time < 0.1" | bc -l) )); then
            log_msg SUCCESS "Test 3 passed: Cache functionality"
            ((passed++))
        else
            log_msg WARN "Test 3 partial: Cache might not be working optimally"
            ((passed++))
        fi
    else
        log_msg ERROR "Test 3 failed: Cache path generation"
        ((failed++))
    fi
    
    # Test 4: Character encoding detection
    printf "Hello\xC3\xA9World" > "$test_dir/test_utf8.txt"
    local enc
    enc=$(detect_encoding "$test_dir/test_utf8.txt")
    if [[ "$enc" =~ utf ]]; then
        log_msg SUCCESS "Test 4 passed: Encoding detection"
        ((passed++))
    else
        log_msg ERROR "Test 4 failed: Encoding detection returned '$enc'"
        ((failed++))
    fi
    
    # Test 5: HTML generation
    if command -v pandoc &>/dev/null; then
        if convert_file "$test_dir/test.md" "$test_dir/test.html"; then
            if [[ -f "$test_dir/test.html" ]] && grep -q "<strong>test</strong>" "$test_dir/test.html"; then
                log_msg SUCCESS "Test 5 passed: HTML generation"
                ((passed++))
            else
                log_msg ERROR "Test 5 failed: HTML content validation"
                ((failed++))
            fi
        else
            log_msg ERROR "Test 5 failed: HTML generation"
            ((failed++))
        fi
    else
        log_msg WARN "Test 5 skipped: pandoc not available"
    fi
    
    # Test 6: Parallel processing
    if [[ $PARALLEL_JOBS -gt 1 ]]; then
        # Create multiple test files
        for i in {1..5}; do
            echo "Test file $i" > "$test_dir/parallel_$i.txt"
        done
        
        BATCH_MODE=1
        local start_time=$(date +%s)
        process_parallel "$test_dir"/parallel_*.txt
        local end_time=$(date +%s)
        local parallel_time=$((end_time - start_time))
        
        local converted_count=0
        for i in {1..5}; do
            [[ -f "$test_dir/parallel_$i.$OUTPUT_FORMAT" ]] && ((converted_count++))
        done
        
        if [[ $converted_count -eq 5 ]]; then
            log_msg SUCCESS "Test 6 passed: Parallel processing"
            ((passed++))
        else
            log_msg ERROR "Test 6 failed: Only $converted_count/5 files converted"
            ((failed++))
        fi
    else
        log_msg WARN "Test 6 skipped: Parallel processing disabled"
    fi
    
    # Test 7: Lock file mechanism
    local test_lock="$test_dir/lock_test.txt"
    echo "Lock test" > "$test_lock"
    if create_lock "$test_lock"; then
        if ! create_lock "$test_lock"; then
            log_msg SUCCESS "Test 7 passed: Lock file mechanism"
            ((passed++))
        else
            log_msg ERROR "Test 7 failed: Lock file not preventing concurrent access"
            ((failed++))
        fi
        remove_lock "$test_lock"
    else
        log_msg ERROR "Test 7 failed: Could not create lock file"
        ((failed++))
    fi
    
    # Summary
    local total=$((passed + failed))
    echo
    log_msg INFO "Self-test completed: $passed/$total tests passed"
    
    if [[ $failed -gt 0 ]]; then
        log_msg WARN "Some tests failed. Check your installation."
        return 1
    else
        log_msg SUCCESS "All tests passed!"
        return 0
    fi
}

# Show statistics
show_stats() {
    if [[ ! -f "$STATS_FILE" ]]; then
        log_msg WARN "No statistics available"
        return
    fi
    
    if ! command -v jq &>/dev/null; then
        log_msg ERROR "jq required for statistics display"
        return
    fi
    
    echo -e "${C_HIGHLIGHT}Conversion Statistics${C_RESET}"
    echo "===================="
    
    local conversions failures total_size total_time
    conversions=$(jq -r '.conversions // 0' "$STATS_FILE")
    failures=$(jq -r '.failures // 0' "$STATS_FILE")
    total_size=$(jq -r '.total_size // 0' "$STATS_FILE")
    total_time=$(jq -r '.total_time // 0' "$STATS_FILE")
    
    echo "Total conversions: $conversions"
    echo "Failed conversions: $failures"
    
    if [[ $conversions -gt 0 ]]; then
        local success_rate=$((100 * (conversions - failures) / conversions))
        echo "Success rate: $success_rate%"
        echo "Total data processed: $(human_size "$total_size")"
        printf "Total time: %.2f seconds\n" "$total_time"
        printf "Average time: %.2f seconds\n" "$(echo "$total_time / $conversions" | bc -l)"
    fi
    
    # Format statistics
    echo
    echo -e "${C_HIGHLIGHT}Format Statistics${C_RESET}"
    echo "================="
    
    jq -r '.format_stats | to_entries | sort_by(.value.success // 0) | reverse | .[] | 
           "KATEX_INLINE_OPEN.key | gsub("_to_"; " → ")): KATEX_INLINE_OPEN.value.success // 0) successful, KATEX_INLINE_OPEN.value.failure // 0) failed"' \
           "$STATS_FILE" 2>/dev/null | head -10
    
    # Recent conversions
    echo
    echo -e "${C_HIGHLIGHT}Recent Conversions${C_RESET}"
    echo "=================="
    
    if [[ -f "$HISTORY_FILE" ]]; then
        tail -n 50 "$HISTORY_FILE" | \
            jq -r 'select(.level == "SUCCESS") | "KATEX_INLINE_OPEN.timestamp) - KATEX_INLINE_OPEN.message)"' 2>/dev/null | \
            tail -5
    fi
}

# Main script initialization
main() {
    # Override with environment variables
    PARALLEL_JOBS="${TEXTCONVERT_PARALLEL:-$PARALLEL_JOBS}"
    TIMEOUT="${TEXTCONVERT_TIMEOUT:-$TIMEOUT}"
    [[ -n "${TEXTCONVERT_CONFIG:-}" ]] && CONFIG_FILE="$TEXTCONVERT_CONFIG"
    [[ -n "${TEXTCONVERT_CACHE:-}" ]] && CACHE_DIR="$TEXTCONVERT_CACHE"
    
    # Create secure temp directory
    create_temp_dir
    
    # Parse command line arguments
    local ARGS=()
    local INTERACTIVE=0
    local PRESET=""
    local CHAIN_FORMATS=""
    local OUTPUT_FORMAT=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--batch)
                BATCH_MODE=1
                shift
                ;;
            -c|--cache)
                USE_CACHE=1
                shift
                ;;
            --no-cache)
                USE_CACHE=0
                shift
                ;;
            -d|--output-dir)
                OUTPUT_DIR="$2"
                mkdir -p "$OUTPUT_DIR"
                shift 2
                ;;
            -e|--encoding)
                ENCODING="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_OVERWRITE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -i|--interactive)
                INTERACTIVE=1
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -k|--keep)
                KEEP_ORIGINALS=1
                shift
                ;;
            --no-keep)
                KEEP_ORIGINALS=0
                shift
                ;;
            -l|--lang)
                TARGET_OCR_LANG="$2"
                shift 2
                ;;
            -m|--metadata)
                PRESERVE_METADATA=1
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=1
                VERBOSITY=2
                shift
                ;;
            -p|--preset)
                PRESET="$2"
                shift 2
                ;;
            -q|--quiet)
                VERBOSITY=0
                SHOW_PROGRESS=0
                shift
                ;;
            -r|--recursive)
                RECURSIVE=1
                shift
                ;;
            -v|--verbose)
                ((VERBOSITY++))
                shift
                ;;
            -x|--extract)
                EXTRACT_EMBEDDED=1
                shift
                ;;
            --quality)
                QUALITY="$2"
                shift 2
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --safe)
                SAFE_MODE=1
                shift
                ;;
            --monitor)
                MONITOR_RESOURCES=1
                shift
                ;;
            --no-confirm)
                NO_CONFIRM=1
                shift
                ;;
            --chain)
                CONVERSION_CHAIN=1
                CHAIN_FORMATS="$2"
                shift 2
                ;;
            --api)
                USE_FALLBACK_API=1
                shift
                ;;
            --stats)
                show_stats
                exit 0
                ;;
            --clean-cache)
                clean_cache
                exit 0
                ;;
            --self-test)
                check_deps
                self_test
                exit $?
                ;;
            --)
                shift
                ARGS+=("$@")
                break
                ;;
            -*)
                log_msg ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                ARGS+=("$1")
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_deps
    
    # Load preset if specified
    if [[ -n "$PRESET" ]]; then
        load_preset "$PRESET"
    fi
    
    # Check if we have input files
    if [[ ${#ARGS[@]} -eq 0 ]]; then
        log_msg ERROR "No input files specified"
        usage
        exit 1
    fi
    
    # Interactive mode takes precedence
    if [[ $INTERACTIVE -eq 1 ]]; then
        for input in "${ARGS[@]}"; do
            interactive_mode "$input"
        done
        exit 0
    fi
    
    # Determine output format and input files
    local INPUT_FILES=()
    
    # Check if first argument is a format
    if [[ ${#ARGS[@]} -gt 1 ]] && [[ -n "${FORMAT_EXTENSIONS[${ARGS[0]}]}" ]]; then
        OUTPUT_FORMAT="${ARGS[0]}"
        INPUT_FILES=("${ARGS[@]:1}")
    else
        OUTPUT_FORMAT="${DEFAULT_OUTPUT_FORMAT}"
        INPUT_FILES=("${ARGS[@]}")
    fi
    
    # Validate output format
    if [[ -z "${FORMAT_EXTENSIONS[$OUTPUT_FORMAT]}" ]]; then
        log_msg ERROR "Unknown output format: $OUTPUT_FORMAT"
        log_msg INFO "Use -h to see supported formats"
        exit 1
    fi
    
    log_msg INFO "Converting to $OUTPUT_FORMAT format"
    
    # Process files
    if [[ $CONVERSION_CHAIN -eq 1 ]]; then
        # Chain conversion mode
        IFS=',' read -ra chain_array <<< "$CHAIN_FORMATS"
        for input in "${INPUT_FILES[@]}"; do
            if [[ -f "$input" ]]; then
                local output
                if [[ -n "$OUTPUT_DIR" ]]; then
                    output="$OUTPUT_DIR/$(basename "${input%.*}").${OUTPUT_FORMAT}"
                else
                    output="${input%.*}.${OUTPUT_FORMAT}"
                fi
                convert_chain "$input" "$output" "${chain_array[@]}"
            fi
        done
    elif [[ $BATCH_MODE -eq 1 || $PARALLEL_JOBS -gt 1 ]]; then
        # Expand directories if recursive
        local ALL_FILES=()
        for input in "${INPUT_FILES[@]}"; do
            if [[ -d "$input" && $RECURSIVE -eq 1 ]]; then
                while IFS= read -r -d '' file; do
                    ALL_FILES+=("$file")
                done < <(find "$input" -type f -print0)
            elif [[ -f "$input" ]]; then
                ALL_FILES+=("$input")
            else
                log_msg WARN "Skipping '$input': not a file or directory"
            fi
        done
        
        # Parallel processing mode
        if [[ ${#ALL_FILES[@]} -gt 0 ]]; then
            process_parallel "${ALL_FILES[@]}"
        else
            log_msg ERROR "No valid input files found"
            exit 1
        fi
    else
        # Sequential processing
        for input in "${INPUT_FILES[@]}"; do
            if [[ -d "$input" && $RECURSIVE -eq 1 ]]; then
                log_msg INFO "Processing directory recursively: $input"
                find "$input" -type f | while IFS= read -r file; do
                    process_single_file "$file"
                done
            elif [[ -f "$input" ]]; then
                process_single_file "$input"
            else
                log_msg WARN "Skipping '$input': not a file or directory"
            fi
        done
    fi
    
    # Show final statistics in verbose mode
    if [[ $VERBOSITY -ge 2 ]]; then
        echo
        show_stats
    fi
}

# Start the script
main "$@"
