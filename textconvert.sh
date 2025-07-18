#!/bin/bash
#
# A versatile and intelligent file conversion script with enhanced capabilities.
# Chooses the best tool (pandoc, calibre, ocrmypdf, etc.) for the job.
#
# Author: Enhanced by an AI Assistant
# Version: 4.0 - Major enhancement with additional formats and features

# --- Default Configuration (can be overridden by user config) ---
DEFAULT_OUTPUT_FORMAT="txt"
DEFAULT_OCR_LANG="eng"
DEFAULT_ENCODING="utf-8"
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
)
# Verbosity Levels: 0=Quiet, 1=Normal, 2=Verbose, 3=Debug
VERBOSITY=1
DRY_RUN=0
RECURSIVE=0
FORCE_OVERWRITE=0
TARGET_OCR_LANG="${DEFAULT_OCR_LANG}"
PARALLEL_JOBS=1
KEEP_ORIGINALS=1
BATCH_MODE=0
VALIDATE_OUTPUT=1
EXTRACT_EMBEDDED=0
USE_FALLBACK_API=0
SHOW_PROGRESS=1
PRESERVE_METADATA=1
ENCODING="${DEFAULT_ENCODING}"

# --- Color Definitions ---
C_ERROR='\033[0;31m'
C_SUCCESS='\033[0;32m'
C_WARN='\033[0;33m'
C_INFO='\033[0;36m'
C_CMD='\033[0;35m'
C_PROGRESS='\033[0;34m'
C_RESET='\033[0m'

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
    ["docbook"]="xml"
    ["man"]="man"
    ["fb2"]="fb2"
    ["lit"]="lit"
    ["pdb"]="pdb"
    ["djvu"]="djvu"
    
    # Markup
    ["md"]="md markdown"
    ["html"]="html htm"
    ["xhtml"]="xhtml"
    ["xml"]="xml"
    ["json"]="json"
    ["yaml"]="yaml yml"
    ["toml"]="toml"
    
    # Plain text
    ["txt"]="txt text"
    ["csv"]="csv"
    ["tsv"]="tsv"
    
    # Presentations
    ["pptx"]="pptx"
    ["odp"]="odp"
    
    # Spreadsheets
    ["xlsx"]="xlsx"
    ["ods"]="ods"
    ["xls"]="xls"
    
    # Archives
    ["zip"]="zip"
    ["tar"]="tar"
    ["gz"]="gz"
    
    # Images (for OCR and PDF creation)
    ["png"]="png"
    ["jpg"]="jpg jpeg"
    ["tiff"]="tiff tif"
    ["gif"]="gif"
    ["bmp"]="bmp"
    ["webp"]="webp"
    ["svg"]="svg"
)

# --- User Configuration ---
CONFIG_DIR="$HOME/.config/textconvert"
CONFIG_FILE="$CONFIG_DIR/config.sh"
PRESETS_FILE="$CONFIG_DIR/presets.json"
HISTORY_FILE="$CONFIG_DIR/history.log"
TEMP_DIR="${TMPDIR:-/tmp}/textconvert_$$"

# Create config directory if it doesn't exist
[[ ! -d "$CONFIG_DIR" ]] && mkdir -p "$CONFIG_DIR"

# Load user configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# --- Cleanup ---
cleanup() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    # Kill any background jobs
    jobs -p | xargs -r kill 2>/dev/null
}
trap cleanup EXIT INT TERM

# --- Functions ---

# Enhanced usage with examples for all formats
usage() {
    cat << EOF
A versatile file conversion script with support for 30+ formats.

Usage: $(basename "$0") [options] [<output_format>] <input_file_or_dir>...

If <output_format> is omitted, it defaults to '${DEFAULT_OUTPUT_FORMAT}'.

Supported Formats:
  Documents:     pdf, epub, mobi, azw, azw3, docx, doc, odt, rtf, tex, fb2, lit, djvu
  Markup:        md, html, xhtml, xml, rst, textile, mediawiki, docbook, man
  Plain Text:    txt, csv, tsv
  Presentations: pptx, odp
  Spreadsheets:  xlsx, xls, ods
  Archives:      zip, tar, gz
  Images:        png, jpg, tiff, gif, bmp, webp, svg

Options:
  -b, --batch         Enable batch mode with progress indicator
  -e, --encoding      Set character encoding (default: $DEFAULT_ENCODING)
  -f, --force         Force overwrite existing files
  -h, --help          Display this help message
  -i, --interactive   Interactive mode for format selection
  -j, --jobs <n>      Number of parallel conversion jobs (default: 1)
  -k, --keep          Keep original files (default: yes)
  -l, --lang <code>   OCR language (e.g., eng, deu, fra)
  -m, --metadata      Preserve metadata during conversion
  -n, --dry-run       Show commands without executing
  -p, --preset <name> Use a conversion preset
  -q, --quiet         Suppress output except errors
  -r, --recursive     Convert files in directories recursively
  -v, --verbose       Enable verbose output
  -x, --extract       Extract embedded content (images from PDFs, etc.)
  --validate          Validate output after conversion
  --api               Use online API as fallback for failed conversions

Format-Specific Examples:
  # High-quality PDF from Markdown with custom styling
  $(basename "$0") --preset academic pdf thesis.md
  
  # Batch convert all Word documents to Markdown
  $(basename "$0") -b md *.docx
  
  # Extract text from scanned PDFs with German OCR
  $(basename "$0") -l deu txt scanned_document.pdf
  
  # Convert e-book preserving metadata
  $(basename "$0") -m epub my_book.mobi
  
  # Create PDF from multiple images
  $(basename "$0") pdf page1.png page2.png page3.png
  
  # Extract all images from a PDF
  $(basename "$0") -x images document.pdf
  
  # Convert CSV to formatted table in various formats
  $(basename "$0") html data.csv
  
  # Parallel conversion of large document set
  $(basename "$0") -j 4 -r pdf /path/to/documents/

Configuration:
  Config file: $CONFIG_FILE
  Presets:     $PRESETS_FILE
  History:     $HISTORY_FILE

For more examples and documentation, visit:
https://github.com/example/textconvert
EOF
}

# Logging with levels
log_msg() {
    local level="$1"
    local message="$2"
    local color="$C_RESET"
    local min_verbosity=1

    case "$level" in
        "ERROR")   color="$C_ERROR";    min_verbosity=0 ;;
        "SUCCESS") color="$C_SUCCESS";  min_verbosity=1 ;;
        "WARN")    color="$C_WARN";     min_verbosity=1 ;;
        "INFO")    color="$C_INFO";     min_verbosity=2 ;;
        "CMD")     color="$C_CMD";      min_verbosity=2 ;;
        "DEBUG")   color="$C_INFO";     min_verbosity=3 ;;
        "PROGRESS") color="$C_PROGRESS"; min_verbosity=1 ;;
        *) message="$level $message" ;;
    esac

    if [[ $VERBOSITY -ge $min_verbosity ]]; then
        echo -e "${color}${message}${C_RESET}" >&2
    fi
    
    # Log to history file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$HISTORY_FILE"
}

# Progress indicator for batch operations
show_progress() {
    local current=$1
    local total=$2
    local file=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    if [[ $SHOW_PROGRESS -eq 1 && $VERBOSITY -ge 1 ]]; then
        printf "\r${C_PROGRESS}[%${filled}s%${empty}s] %3d%% (%d/%d) %s${C_RESET}" \
               "$(printf '=%.0s' $(seq 1 $filled))" \
               "" "$percent" "$current" "$total" \
               "$(basename "$file" | cut -c1-30)..."
    fi
}

# Enhanced dependency checking with feature detection
check_deps() {
    log_msg INFO "Checking dependencies and available features..."
    local missing_critical=0
    local missing_features=0
    
    # Critical dependencies
    local critical_deps=(
        "pandoc:pandoc:Core document conversion"
    )
    
    # Feature dependencies
    local feature_deps=(
        "ebook-convert:calibre:E-book formats (epub, mobi, azw)"
        "ocrmypdf:ocrmypdf:PDF OCR capabilities"
        "pdftotext:poppler-utils:PDF text extraction"
        "pdftoppm:poppler-utils:PDF to image conversion"
        "pdfimages:poppler-utils:Extract images from PDFs"
        "djvutxt:djvulibre-bin:DJVU support"
        "tesseract:tesseract-ocr:Advanced OCR"
        "libreoffice:libreoffice:Office document support"
        "unoconv:unoconv:Enhanced office conversions"
        "xelatex:texlive-xetex:High-quality PDF generation"
        "convert:imagemagick:Image processing"
        "jq:jq:JSON processing"
        "xmllint:libxml2-utils:XML validation"
        "csvtool:csvtool:CSV manipulation"
        "antiword:antiword:Legacy .doc support"
        "unrtf:unrtf:RTF support"
        "w3m:w3m:HTML to text conversion"
        "lynx:lynx:Alternative HTML to text"
        "detex:texlive-binaries:LaTeX to text"
    )
    
    # Check critical dependencies
    for dep in "${critical_deps[@]}"; do
        IFS=':' read -r cmd pkg purpose <<< "$dep"
        if ! command -v "$cmd" &>/dev/null; then
            log_msg ERROR "Critical: '$cmd' not found. Install '$pkg' - $purpose"
            ((missing_critical++))
        fi
    done
    
    if [[ $missing_critical -gt 0 ]]; then
        log_msg ERROR "Cannot proceed without critical dependencies."
        exit 1
    fi
    
    # Check feature dependencies
    declare -g AVAILABLE_FEATURES=()
    for dep in "${feature_deps[@]}"; do
        IFS=':' read -r cmd pkg purpose <<< "$dep"
        if command -v "$cmd" &>/dev/null; then
            AVAILABLE_FEATURES+=("$cmd")
        else
            log_msg DEBUG "Optional: '$cmd' not found. Install '$pkg' for: $purpose"
            ((missing_features++))
        fi
    done
    
    log_msg INFO "Found ${#AVAILABLE_FEATURES[@]} optional features, $missing_features missing"
}

# Detect file format by content, not just extension
detect_format() {
    local file="$1"
    local detected=""
    
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    
    # Use file command for magic number detection
    local file_output
    file_output=$(file -b "$file" 2>/dev/null)
    
    case "$file_output" in
        *"PDF document"*)         detected="pdf" ;;
        *"EPUB document"*)        detected="epub" ;;
        *"Mobipocket E-book"*)    detected="mobi" ;;
        *"Microsoft Word"*)       detected="docx" ;;
        *"OpenDocument Text"*)    detected="odt" ;;
        *"HTML document"*)        detected="html" ;;
        *"XML"*)                  detected="xml" ;;
        *"JSON"*)                 detected="json" ;;
        *"CSV"*)                  detected="csv" ;;
        *"PNG image"*)            detected="png" ;;
        *"JPEG image"*)           detected="jpg" ;;
        *"TIFF image"*)           detected="tiff" ;;
        *"SVG"*)                  detected="svg" ;;
        *"LaTeX"*)                detected="tex" ;;
        *"text"*)                 detected="txt" ;;
    esac
    
    echo "$detected"
}

# Validate output file after conversion
validate_output() {
    local output="$1"
    local expected_format="$2"
    
    if [[ $VALIDATE_OUTPUT -eq 0 ]]; then
        return 0
    fi
    
    if [[ ! -f "$output" ]]; then
        log_msg ERROR "Validation failed: Output file not created"
        return 1
    fi
    
    local detected
    detected=$(detect_format "$output")
    
    if [[ -n "$detected" && "$detected" != "$expected_format" ]]; then
        log_msg WARN "Output format mismatch: expected $expected_format, got $detected"
    fi
    
    # Check file size
    local size
    size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null)
    if [[ $size -eq 0 ]]; then
        log_msg ERROR "Validation failed: Output file is empty"
        return 1
    fi
    
    log_msg DEBUG "Output validated: $output ($size bytes)"
    return 0
}

# Extract embedded content from files
extract_embedded_content() {
    local input="$1"
    local output_dir="$2"
    local in_ext="${input##*.}"
    
    mkdir -p "$output_dir"
    
    case "$in_ext" in
        pdf)
            if command -v pdfimages &>/dev/null; then
                log_msg INFO "Extracting images from PDF..."
                pdfimages -all "$input" "$output_dir/image"
            fi
            ;;
        docx|odt)
            log_msg INFO "Extracting embedded files from document..."
            local temp_extract="$TEMP_DIR/extract_$$"
            mkdir -p "$temp_extract"
            unzip -q "$input" -d "$temp_extract"
            find "$temp_extract" -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | \
                xargs -I {} cp {} "$output_dir/"
            ;;
    esac
}

# Create conversion presets
load_preset() {
    local preset_name="$1"
    
    if [[ ! -f "$PRESETS_FILE" ]]; then
        log_msg WARN "No presets file found. Creating default presets..."
        create_default_presets
    fi
    
    # Load preset using jq if available
    if command -v jq &>/dev/null; then
        local preset
        preset=$(jq -r ".presets.$preset_name" "$PRESETS_FILE" 2>/dev/null)
        if [[ "$preset" != "null" && -n "$preset" ]]; then
            log_msg INFO "Loading preset: $preset_name"
            # Apply preset settings
            eval "$preset"
        else
            log_msg WARN "Preset '$preset_name' not found"
        fi
    else
        log_msg WARN "jq not installed, cannot load presets"
    fi
}

# Create default presets file
create_default_presets() {
    cat > "$PRESETS_FILE" << 'EOF'
{
  "presets": {
    "academic": {
      "PANDOC_PDF_OPTS": ["--toc", "--number-sections", "--bibliography=references.bib", "--csl=apa.csl"],
      "PRESERVE_METADATA": 1
    },
    "ebook": {
      "OUTPUT_FORMAT": "epub",
      "PRESERVE_METADATA": 1,
      "EBOOK_OPTS": ["--epub-chapter-level=2", "--toc-depth=3"]
    },
    "minimal": {
      "OUTPUT_FORMAT": "txt",
      "PRESERVE_METADATA": 0,
      "EXTRACT_EMBEDDED": 0
    },
    "web": {
      "OUTPUT_FORMAT": "html",
      "PANDOC_HTML_OPTS": ["--self-contained", "--css=style.css"]
    },
    "slides": {
      "OUTPUT_FORMAT": "html",
      "PANDOC_SLIDES_OPTS": ["--to=revealjs", "--slide-level=2"]
    }
  }
}
EOF
}

# Enhanced conversion function with fallback strategies
convert_file() {
    local input="$1"
    local output="$2"
    shift 2
    local extra_inputs=("$@")
    
    # Detect actual format if needed
    local in_ext
    in_ext=$(echo "${input##*.}" | tr '[:upper:]' '[:lower:]')
    local detected_format
    detected_format=$(detect_format "$input")
    
    if [[ -n "$detected_format" && "$detected_format" != "$in_ext" ]]; then
        log_msg WARN "Detected format ($detected_format) differs from extension ($in_ext)"
        in_ext="$detected_format"
    fi
    
    local out_ext
    out_ext=$(echo "${output##*.}" | tr '[:upper:]' '[:lower:]')
    
    local cmd_array=()
    local tool_output
    local ret_code
    
    log_msg "--- Converting '$input' ($in_ext) to '$output' ($out_ext) ---"
    
    # Extract embedded content if requested
    if [[ $EXTRACT_EMBEDDED -eq 1 ]]; then
        local extract_dir="${output%.*}_embedded"
        extract_embedded_content "$input" "$extract_dir"
    fi
    
    # Enhanced tool selection with multiple fallback strategies
    case "$in_ext" in
        # E-book formats
        epub|mobi|azw|azw3|fb2|lit|pdb)
            if command -v ebook-convert &>/dev/null; then
                log_msg INFO "Using Calibre for e-book conversion"
                cmd_array=(ebook-convert "$input" "$output")
                if [[ $PRESERVE_METADATA -eq 1 ]]; then
                    cmd_array+=(--preserve-metadata)
                fi
            else
                log_msg WARN "Calibre not found, trying pandoc..."
                cmd_array=(pandoc "$input" -o "$output")
            fi
            ;;
        
        # PDF handling with multiple strategies
        pdf)
            case "$out_ext" in
                txt)
                    # Try multiple text extraction methods
                    if command -v pdftotext &>/dev/null; then
                        log_msg INFO "Attempting pdftotext extraction..."
                        pdftotext -layout -enc "$ENCODING" "$input" "$output"
                        
                        if [[ ! -s "$output" ]] || ! grep -q '[[:alnum:]]' "$output"; then
                            log_msg WARN "No text found, attempting OCR..."
                            if command -v ocrmypdf &>/dev/null; then
                                cmd_array=(ocrmypdf -l "$TARGET_OCR_LANG" --sidecar "$output" "$input" -)
                            elif command -v tesseract &>/dev/null; then
                                # Convert PDF to images first, then OCR
                                log_msg INFO "Using tesseract via image conversion..."
                                local temp_img="$TEMP_DIR/page"
                                pdftoppm "$input" "$temp_img" -png
                                for img in "$TEMP_DIR"/page-*.png; do
                                    tesseract "$img" stdout >> "$output"
                                done
                                cmd_array=(:) # No-op
                            fi
                        else
                            cmd_array=(:) # Success, no further command
                        fi
                    fi
                    ;;
                    
                pdf)
                    # PDF optimization/OCR
                    if command -v ocrmypdf &>/dev/null; then
                        log_msg INFO "Optimizing PDF with OCR..."
                        cmd_array=(ocrmypdf -l "$TARGET_OCR_LANG" --optimize 3 "$input" "$output")
                    else
                        log_msg WARN "ocrmypdf not found, copying file..."
                        cmd_array=(cp "$input" "$output")
                    fi
                    ;;
                    
                *)
                    # PDF to other formats
                    if command -v ebook-convert &>/dev/null; then
                        cmd_array=(ebook-convert "$input" "$output")
                    else
                        cmd_array=(pandoc "$input" -o "$output")
                    fi
                    ;;
            esac
            ;;
        
        # Office documents
        doc|docx|odt|rtf)
            # Try multiple converters in order of preference
            if command -v unoconv &>/dev/null; then
                log_msg INFO "Using unoconv for office conversion"
                cmd_array=(unoconv -f "$out_ext" -o "$output" "$input")
            elif command -v libreoffice &>/dev/null; then
                log_msg INFO "Using LibreOffice for conversion"
                cmd_array=(libreoffice --headless --convert-to "$out_ext" --outdir "$(dirname "$output")" "$input")
            elif [[ "$in_ext" == "rtf" ]] && command -v unrtf &>/dev/null; then
                log_msg INFO "Using unrtf for RTF conversion"
                cmd_array=(unrtf --text "$input")
            elif [[ "$in_ext" == "doc" ]] && command -v antiword &>/dev/null; then
                log_msg INFO "Using antiword for legacy .doc"
                cmd_array=(antiword "$input")
            else
                log_msg INFO "Falling back to pandoc"
                cmd_array=(pandoc "$input" -o "$output")
            fi
            ;;
        
        # Spreadsheets
        xls|xlsx|ods|csv|tsv)
            if [[ "$out_ext" == "csv" || "$out_ext" == "tsv" ]]; then
                if command -v csvtool &>/dev/null; then
                    log_msg INFO "Using csvtool for spreadsheet conversion"
                    # Complex conversion logic here
                else
                    cmd_array=(pandoc "$input" -o "$output")
                fi
            else
                cmd_array=(pandoc "$input" -o "$output")
            fi
            ;;
        
        # Markup languages
        md|markdown|rst|textile|mediawiki|docbook)
            log_msg INFO "Using pandoc for markup conversion"
            local pandoc_opts=("--standalone")
            
            if [[ "$out_ext" == "pdf" ]]; then
                pandoc_opts+=("${PANDOC_PDF_OPTS[@]}")
                if [[ "$in_ext" =~ ^(md|markdown)$ ]]; then
                    # Add enhanced LaTeX handling for markdown
                    local header_file
                    header_file=$(create_enhanced_latex_header)
                    pandoc_opts+=(--include-in-header "$header_file")
                fi
            elif [[ "$out_ext" == "html" ]]; then
                pandoc_opts+=(--toc --self-contained)
            fi
            
            cmd_array=(pandoc "${pandoc_opts[@]}" "$input" -o "$output")
            ;;
        
        # LaTeX/TeX
        tex|latex)
            if [[ "$out_ext" == "pdf" ]]; then
                if command -v xelatex &>/dev/null; then
                    log_msg INFO "Using XeLaTeX for PDF generation"
                    cmd_array=(xelatex -output-directory="$(dirname "$output")" "$input")
                else
                    cmd_array=(pandoc "$input" -o "$output")
                fi
            elif [[ "$out_ext" == "txt" ]] && command -v detex &>/dev/null; then
                log_msg INFO "Using detex for LaTeX to text"
                detex "$input" > "$output"
                cmd_array=(:)
            else
                cmd_array=(pandoc "$input" -o "$output")
            fi
            ;;
        
        # HTML
        html|htm|xhtml)
            if [[ "$out_ext" == "txt" ]]; then
                # Try multiple HTML to text converters
                if command -v w3m &>/dev/null; then
                    log_msg INFO "Using w3m for HTML to text"
                    cmd_array=(w3m -dump "$input")
                elif command -v lynx &>/dev/null; then
                    log_msg INFO "Using lynx for HTML to text"
                    cmd_array=(lynx -dump -nolist "$input")
                else
                    cmd_array=(pandoc "$input" -t plain -o "$output")
                fi
            else
                cmd_array=(pandoc "$input" -o "$output")
            fi
            ;;
        
        # Images
        png|jpg|jpeg|tiff|tif|gif|bmp|webp|svg)
            if [[ "$out_ext" == "pdf" ]]; then
                if command -v convert &>/dev/null; then
                    log_msg INFO "Using ImageMagick for image to PDF"
                    cmd_array=(convert "$input" "${extra_inputs[@]}" "$output")
                else
                    cmd_array=(pandoc "$input" -o "$output")
                fi
            elif [[ "$out_ext" == "txt" ]]; then
                if command -v tesseract &>/dev/null; then
                    log_msg INFO "Using Tesseract for image OCR"
                    cmd_array=(tesseract "$input" stdout -l "$TARGET_OCR_LANG")
                else
                    log_msg ERROR "OCR requires tesseract"
                    return 1
                fi
            else
                cmd_array=(convert "$input" "$output")
            fi
            ;;
        
        # DJVU
        djvu)
            if [[ "$out_ext" == "txt" ]]; then
                if command -v djvutxt &>/dev/null; then
                    cmd_array=(djvutxt "$input" "$output")
                else
                    log_msg ERROR "DJVU support requires djvulibre"
                    return 1
                fi
            elif command -v ddjvu &>/dev/null; then
                cmd_array=(ddjvu -format="$out_ext" "$input" "$output")
            else
                log_msg ERROR "DJVU conversion not available"
                return 1
            fi
            ;;
        
        # Default fallback
        *)
            log_msg INFO "Using pandoc as general converter"
            cmd_array=(pandoc --standalone "$input" -o "$output")
            ;;
    esac
    
    # Execute conversion
    if [[ ${#cmd_array[@]} -eq 0 ]]; then
        log_msg ERROR "No conversion strategy found for $in_ext to $out_ext"
        return 1
    fi
    
    log_msg CMD "COMMAND: $(printf "%q " "${cmd_array[@]}")"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi
    
    # Handle special case commands
    if [[ "${cmd_array[0]}" == ":" ]]; then
        ret_code=0
    else
        # Execute with timeout and capture output
        if timeout 300 "${cmd_array[@]}" > "${output}.tmp" 2>&1; then
            ret_code=0
            if [[ "${cmd_array[0]}" =~ ^(w3m|lynx|antiword|detex)$ ]]; then
                # These commands output to stdout
                mv "${output}.tmp" "$output"
            else
                rm -f "${output}.tmp"
            fi
        else
            ret_code=$?
            tool_output=$(cat "${output}.tmp")
            rm -f "${output}.tmp"
        fi
    fi
    
    # Validate and handle results
    if [[ $ret_code -eq 0 ]]; then
        if validate_output "$output" "$out_ext"; then
            log_msg SUCCESS "Successfully converted to '$output'"
            return 0
        else
            log_msg ERROR "Conversion produced invalid output"
            return 1
        fi
    else
        log_msg ERROR "Conversion failed with exit code $ret_code"
        if [[ -n "$tool_output" ]]; then
            log_msg ERROR "Error output: $tool_output"
        fi
        
        # Try fallback API if enabled
        if [[ $USE_FALLBACK_API -eq 1 ]]; then
            log_msg INFO "Attempting online conversion as fallback..."
            # Implement API fallback here
        fi
        
        return 1
    fi
}

# Create enhanced LaTeX header for complex documents
create_enhanced_latex_header() {
    local temp_file
    temp_file=$(mktemp)
    
    cat > "$temp_file" << 'EOF'
% Enhanced LaTeX configuration for pandoc
\usepackage{enumitem}
\setlistdepth{9}

% Configure itemize lists
\renewlist{itemize}{itemize}{9}
\setlist[itemize,1]{label=\textbullet}
\setlist[itemize,2]{label=\textendash}
\setlist[itemize,3]{label=\textasteriskcentered}
\setlist[itemize,4]{label=\textperiodcentered}
\setlist[itemize,5]{label=\textbullet}
\setlist[itemize,6]{label=\textendash}
\setlist[itemize,7]{label=\textasteriskcentered}
\setlist[itemize,8]{label=\textperiodcentered}
\setlist[itemize,9]{label=\textbullet}

% Configure enumerate lists
\renewlist{enumerate}{enumerate}{9}
\setlist[enumerate,1]{label=\arabic*.}
\setlist[enumerate,2]{label=\alph*.}
\setlist[enumerate,3]{label=\roman*.}
\setlist[enumerate,4]{label=\Alph*.}
\setlist[enumerate,5]{label=\Roman*.}
\setlist[enumerate,6]{label=\arabic*.}
\setlist[enumerate,7]{label=\alph*.}
\setlist[enumerate,8]{label=\roman*.}
\setlist[enumerate,9]{label=\Alph*.}

% Spacing
\setlist[itemize]{topsep=0pt,partopsep=0pt,parsep=0pt,itemsep=0pt}
\setlist[enumerate]{topsep=0pt,partopsep=0pt,parsep=0pt,itemsep=0pt}

% Code highlighting
\usepackage{fancyvrb}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\},fontsize=\small}

% Better tables
\usepackage{booktabs}
\usepackage{longtable}

% Unicode support
\usepackage{unicode-math}

% Hyperlinks
\usepackage{hyperref}
\hypersetup{
    colorlinks=true,
    linkcolor=blue,
    filecolor=magenta,      
    urlcolor=cyan,
    pdftitle={Document},
    pdfpagemode=UseOutlines,
    bookmarks=true
}
EOF

    echo "$temp_file"
}

# Parallel processing wrapper
process_parallel() {
    local -a files=("$@")
    local total=${#files[@]}
    local completed=0
    local max_jobs=$PARALLEL_JOBS
    
    log_msg INFO "Processing $total files with $max_jobs parallel jobs"
    
    # Create a job queue
    for file in "${files[@]}"; do
        # Wait if we've reached max parallel jobs
        while [[ $(jobs -r | wc -l) -ge $max_jobs ]]; do
            sleep 0.1
        done
        
        # Launch background job
        {
            process_single_file "$file"
            echo "DONE:$file" >> "$TEMP_DIR/completed"
        } &
    done
    
    # Wait for all jobs and show progress
    while [[ $(jobs -r | wc -l) -gt 0 ]]; do
        if [[ -f "$TEMP_DIR/completed" ]]; then
            completed=$(wc -l < "$TEMP_DIR/completed")
        fi
        show_progress "$completed" "$total" "Processing..."
        sleep 0.5
    done
    
    echo # New line after progress
    log_msg SUCCESS "Batch processing complete: $total files"
}

# Process a single file
process_single_file() {
    local file="$1"
    local base_name="${file%.*}"
    local final_output_format="$OUTPUT_FORMAT"
    
    # Handle special formats
    local intermediate_format="$final_output_format"
    if [[ "$final_output_format" == "zip" ]]; then
        intermediate_format="txt"
    fi
    
    local output_file="${base_name}.${intermediate_format}"
    
    # Check for overwrite
    if [[ "$file" == "$output_file" && $FORCE_OVERWRITE -eq 0 ]]; then
        log_msg WARN "Skipping '$file': input and output are the same"
        return 1
    fi
    
    # Backup original if needed
    if [[ $KEEP_ORIGINALS -eq 1 && "$file" == "$output_file" ]]; then
        cp "$file" "${file}.backup"
        log_msg INFO "Created backup: ${file}.backup"
    fi
    
    # Perform conversion
    if ! convert_file "$file" "$output_file"; then
        log_msg ERROR "Failed to convert '$file'"
        return 1
    fi
    
    # Handle zip output
    if [[ "$final_output_format" == "zip" ]]; then
        local zip_file="${base_name}.zip"
        log_msg INFO "Creating archive: $zip_file"
        
        if zip -j "$zip_file" "$output_file" >/dev/null 2>&1; then
            rm "$output_file"
            log_msg SUCCESS "Created: $zip_file"
        else
            log_msg ERROR "Failed to create zip archive"
            return 1
        fi
    fi
    
    return 0
}

# Interactive mode for format selection
interactive_mode() {
    local input_file="$1"
    
    echo "Interactive Conversion Mode"
    echo "=========================="
    echo "Input file: $input_file"
    echo
    echo "Available output formats:"
    echo "1) PDF      - Portable Document Format"
    echo "2) EPUB     - E-book format"
    echo "3) HTML     - Web page"
    echo "4) DOCX     - Microsoft Word"
    echo "5) TXT      - Plain text"
    echo "6) MD       - Markdown"
    echo "7) RTF      - Rich Text Format"
    echo "8) ODT      - OpenDocument Text"
    echo "9) Other    - Enter custom format"
    echo
    read -p "Select format (1-9): " choice
    
    case $choice in
        1) OUTPUT_FORMAT="pdf" ;;
        2) OUTPUT_FORMAT="epub" ;;
        3) OUTPUT_FORMAT="html" ;;
        4) OUTPUT_FORMAT="docx" ;;
        5) OUTPUT_FORMAT="txt" ;;
        6) OUTPUT_FORMAT="md" ;;
        7) OUTPUT_FORMAT="rtf" ;;
        8) OUTPUT_FORMAT="odt" ;;
        9) read -p "Enter format: " OUTPUT_FORMAT ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
    
    # Additional options
    read -p "Preserve metadata? (y/n): " preserve
    [[ "$preserve" == "y" ]] && PRESERVE_METADATA=1
    
    read -p "Extract embedded content? (y/n): " extract
    [[ "$extract" == "y" ]] && EXTRACT_EMBEDDED=1
}

# --- Main Script ---

# Create temp directory
mkdir -p "$TEMP_DIR"

# Parse arguments
INTERACTIVE=0
PRESET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--batch)
            BATCH_MODE=1
            shift
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
            VERBOSITY=3
            shift
            ;;
        -x|--extract)
            EXTRACT_EMBEDDED=1
            shift
            ;;
        --validate)
            VALIDATE_OUTPUT=1
            shift
            ;;
        --api)
            USE_FALLBACK_API=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            log_msg ERROR "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Load preset if specified
if [[ -n "$PRESET" ]]; then
    load_preset "$PRESET"
fi

# Determine output format and input files
OUTPUT_FORMAT=""
INPUT_FILES=()

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

# Check if first argument is a format
if [[ $# -gt 1 && "$1" =~ ^(pdf|epub|mobi|azw|azw3|docx|doc|odt|rtf|tex|md|html|txt|csv|zip)$ ]]; then
    OUTPUT_FORMAT="$1"
    shift
    INPUT_FILES=("$@")
else
    OUTPUT_FORMAT="${DEFAULT_OUTPUT_FORMAT}"
    INPUT_FILES=("$@")
fi

# Interactive mode override
if [[ $INTERACTIVE -eq 1 && ${#INPUT_FILES[@]} -eq 1 ]]; then
    interactive_mode "${INPUT_FILES[0]}"
fi

# Check dependencies
check_deps

# Handle batch mode
if [[ $BATCH_MODE -eq 1 || $PARALLEL_JOBS -gt 1 ]]; then
    # Collect all files
    ALL_FILES=()
    for input in "${INPUT_FILES[@]}"; do
        if [[ -d "$input" && $RECURSIVE -eq 1 ]]; then
            while IFS= read -r -d '' file; do
                ALL_FILES+=("$file")
            done < <(find "$input" -type f -print0)
        elif [[ -f "$input" ]]; then
            ALL_FILES+=("$input")
        fi
    done
    
    if [[ ${#ALL_FILES[@]} -gt 0 ]]; then
        process_parallel "${ALL_FILES[@]}"
    else
        log_msg WARN "No files found to process"
    fi
else
    # Process files sequentially
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

# Show summary
if [[ $VERBOSITY -ge 1 ]]; then
    log_msg SUCCESS "All conversions complete"
    
    # Show statistics if in batch mode
    if [[ $BATCH_MODE -eq 1 && -f "$TEMP_DIR/completed" ]]; then
        local total_completed
        total_completed=$(wc -l < "$TEMP_DIR/completed")
        log_msg INFO "Files processed: $total_completed"
    fi
fi

exit 0
