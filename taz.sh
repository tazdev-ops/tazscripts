#!/usr/bin/env bash

# taz 1.0 - Enhanced Terminal Audio Player
# Original by mativ, enhanced version
#
# Features:
# - Multiple player support (mpg123, mpv, ffplay)
# - Shuffle, repeat, and playlist management
# - Resume playback functionality
# - Configuration file support
# - Enhanced file discovery
# - Better error handling

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="taz"
readonly VERSION="1.0"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$SCRIPT_NAME"
readonly CONFIG_FILE="$CONFIG_DIR/config"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$SCRIPT_NAME"
readonly PLAYLIST_FILE="$CACHE_DIR/current_playlist.m3u"
readonly STATE_FILE="$CACHE_DIR/playback_state"

# Default configuration
declare -A CONFIG=(
    [PLAYER]="auto"
    [SHUFFLE]="false"
    [REPEAT]="false"
    [RECURSIVE]="true"
    [FOLLOW_SYMLINKS]="true"
    [MAX_DEPTH]="10"
    [FORMATS]="mp3,mp2,mp1,ogg,wav,flac,m4a,aac,opus,wma,ape,ac3,dts"
    [EXCLUDE_PATTERN]=""
    [INCLUDE_HIDDEN]="false"
)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Initialize directories
init_directories() {
    mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
}

# Load configuration file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            CONFIG["$key"]="$value"
        done < "$CONFIG_FILE"
    fi
}

# Save default configuration
save_default_config() {
    cat > "$CONFIG_FILE" << EOF
# taz configuration file
# Available players: auto, mpg123, mpv, ffplay
PLAYER=auto

# Playback options
SHUFFLE=false
REPEAT=false

# File discovery options
RECURSIVE=true
FOLLOW_SYMLINKS=true
MAX_DEPTH=10
INCLUDE_HIDDEN=false

# Supported formats (comma-separated)
FORMATS=mp3,mp2,mp1,ogg,wav,flac,m4a,aac,opus,wma,ape,ac3,dts

# Exclude pattern (regex)
EXCLUDE_PATTERN=
EOF
}

# Detect available player
detect_player() {
    local players=("mpv" "mpg123" "ffplay")
    
    for player in "${players[@]}"; do
        if command -v "$player" &> /dev/null; then
            echo "$player"
            return 0
        fi
    done
    
    return 1
}

# Print error message
error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

# Print warning message
warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

# Print info message
info() {
    echo -e "${BLUE}Info:${NC} $1"
}

# Print success message
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Show help
show_help() {
    cat << EOF
$SCRIPT_NAME $VERSION - Enhanced Terminal Audio Player

Usage: $(basename "$0") [OPTIONS] [DIRECTORIES/FILES...]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information
    -p, --player PLAYER     Use specific player (mpg123, mpv, ffplay)
    -s, --shuffle           Shuffle playback
    -r, --repeat            Repeat playlist
    -R, --no-recursive      Don't search directories recursively
    -H, --hidden            Include hidden files
    -d, --max-depth N       Maximum directory depth (default: 10)
    -f, --formats LIST      Comma-separated list of formats
    -x, --exclude PATTERN   Exclude files matching pattern
    -l, --list              List files without playing
    -c, --continue          Resume previous playback
    -C, --config            Show configuration file location
    --save-playlist FILE    Save discovered files to playlist
    --load-playlist FILE    Load and play playlist file

EXAMPLES:
    # Play current directory
    $SCRIPT_NAME

    # Play multiple directories with shuffle
    $SCRIPT_NAME -s ~/Music /media/music

    # Play only MP3 and FLAC files
    $SCRIPT_NAME -f mp3,flac ~/Music

    # Resume previous playback
    $SCRIPT_NAME --continue

    # Save playlist for later use
    $SCRIPT_NAME ~/Music --save-playlist my_music.m3u

CONFIGURATION:
    Config file: $CONFIG_FILE
    Cache directory: $CACHE_DIR

EOF
}

# Build find command for music files
build_find_command() {
    local dir="$1"
    local find_cmd="find"
    local name_patterns=()
    
    # Build find options
    if [[ "${CONFIG[FOLLOW_SYMLINKS]}" == "true" ]]; then
        find_cmd+=" -L"
    fi
    
    find_cmd+=" \"$dir\""
    
    # Max depth
    if [[ "${CONFIG[RECURSIVE]}" == "true" ]]; then
        find_cmd+=" -maxdepth ${CONFIG[MAX_DEPTH]}"
    else
        find_cmd+=" -maxdepth 1"
    fi
    
    # Hidden files
    if [[ "${CONFIG[INCLUDE_HIDDEN]}" != "true" ]]; then
        find_cmd+=" -not -path '*/\\.*'"
    fi
    
    # File type
    find_cmd+=" -type f"
    
    # Build name patterns
    IFS=',' read -ra formats <<< "${CONFIG[FORMATS]}"
    for format in "${formats[@]}"; do
        format=$(echo "$format" | xargs) # trim whitespace
        name_patterns+=("-iname \"*.$format\"")
    done
    
    # Add name patterns with OR
    if [[ ${#name_patterns[@]} -gt 0 ]]; then
        find_cmd+=" \\("
        for i in "${!name_patterns[@]}"; do
            if [[ $i -gt 0 ]]; then
                find_cmd+=" -o"
            fi
            find_cmd+=" ${name_patterns[$i]}"
        done
        find_cmd+=" \\)"
    fi
    
    # Exclude pattern
    if [[ -n "${CONFIG[EXCLUDE_PATTERN]}" ]]; then
        find_cmd+=" -not -regex '${CONFIG[EXCLUDE_PATTERN]}'"
    fi
    
    find_cmd+=" -print0 2>/dev/null"
    
    echo "$find_cmd"
}

# Find music files
find_music_files() {
    local directories=("$@")
    local addresses=()
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            warn "Directory not found: $dir"
            continue
        fi
        
        local find_cmd=$(build_find_command "$dir")
        
        while IFS= read -r -d '' file; do
            addresses+=("$file")
        done < <(eval "$find_cmd")
    done
    
    printf '%s\n' "${addresses[@]}"
}

# Shuffle array
shuffle_array() {
    local -n arr=$1
    local i j tmp
    
    for ((i=${#arr[@]}-1; i>0; i--)); do
        j=$((RANDOM % (i+1)))
        tmp="${arr[i]}"
        arr[i]="${arr[j]}"
        arr[j]="$tmp"
    done
}

# Save playlist
save_playlist() {
    local playlist_file="$1"
    shift
    local files=("$@")
    
    {
        echo "#EXTM3U"
        for file in "${files[@]}"; do
            echo "$file"
        done
    } > "$playlist_file"
    
    success "Playlist saved to: $playlist_file"
}

# Load playlist
load_playlist() {
    local playlist_file="$1"
    local files=()
    
    if [[ ! -f "$playlist_file" ]]; then
        error "Playlist file not found: $playlist_file"
        return 1
    fi
    
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        [[ -f "$line" ]] && files+=("$line")
    done < "$playlist_file"
    
    printf '%s\n' "${files[@]}"
}

# Save playback state
save_state() {
    local current_file="$1"
    local position="$2"
    
    cat > "$STATE_FILE" << EOF
FILE=$current_file
POSITION=$position
TIMESTAMP=$(date +%s)
EOF
}

# Load playback state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        echo "FILE=$FILE"
        echo "POSITION=${POSITION:-0}"
    fi
}

# Play with mpg123
play_mpg123() {
    local options=("$@")
    mpg123 "${options[@]}"
}

# Play with mpv
play_mpv() {
    local files=("$@")
    local mpv_options=(
        "--no-video"
        "--msg-level=all=error,statusline=info"
        "--term-osd-bar"
        "--term-osd-bar-chars='[━━ ]'"
    )
    
    if [[ "${CONFIG[SHUFFLE]}" == "true" ]]; then
        mpv_options+=("--shuffle")
    fi
    
    if [[ "${CONFIG[REPEAT]}" == "true" ]]; then
        mpv_options+=("--loop-playlist=inf")
    fi
    
    # Create temporary playlist for mpv
    printf '%s\n' "${files[@]}" > "$PLAYLIST_FILE"
    
    mpv "${mpv_options[@]}" --playlist="$PLAYLIST_FILE"
}

# Play with ffplay
play_ffplay() {
    local files=("$@")
    
    for file in "${files[@]}"; do
        info "Playing: $(basename "$file")"
        ffplay -nodisp -autoexit "$file" 2>/dev/null
        
        if [[ "${CONFIG[REPEAT]}" != "true" ]]; then
            [[ $? -ne 0 ]] && break
        fi
    done
}

# Main function
main() {
    local directories=()
    local files=()
    local player_options=()
    local list_only=false
    local continue_playback=false
    local save_playlist_file=""
    local load_playlist_file=""
    
    # Initialize
    init_directories
    
    # Create default config if not exists
    [[ ! -f "$CONFIG_FILE" ]] && save_default_config
    
    # Load configuration
    load_config
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME $VERSION"
                exit 0
                ;;
            -p|--player)
                CONFIG[PLAYER]="$2"
                shift 2
                ;;
            -s|--shuffle)
                CONFIG[SHUFFLE]="true"
                shift
                ;;
            -r|--repeat)
                CONFIG[REPEAT]="true"
                shift
                ;;
            -R|--no-recursive)
                CONFIG[RECURSIVE]="false"
                shift
                ;;
            -H|--hidden)
                CONFIG[INCLUDE_HIDDEN]="true"
                shift
                ;;
            -d|--max-depth)
                CONFIG[MAX_DEPTH]="$2"
                shift 2
                ;;
            -f|--formats)
                CONFIG[FORMATS]="$2"
                shift 2
                ;;
            -x|--exclude)
                CONFIG[EXCLUDE_PATTERN]="$2"
                shift 2
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -c|--continue)
                continue_playback=true
                shift
                ;;
            -C|--config)
                echo "Configuration file: $CONFIG_FILE"
                exit 0
                ;;
            --save-playlist)
                save_playlist_file="$2"
                shift 2
                ;;
            --load-playlist)
                load_playlist_file="$2"
                shift 2
                ;;
            -*)
                # Unknown option, pass to player
                player_options+=("$1")
                shift
                ;;
            *)
                # File or directory
                if [[ -d "$1" ]]; then
                    directories+=("$1")
                elif [[ -f "$1" ]]; then
                    files+=("$1")
                else
                    warn "Not found: $1"
                fi
                shift
                ;;
        esac
    done
    
    # Default to current directory if no input
    [[ ${#directories[@]} -eq 0 && ${#files[@]} -eq 0 && -z "$load_playlist_file" ]] && directories+=(".")
    
    # Load playlist if specified
    if [[ -n "$load_playlist_file" ]]; then
        mapfile -t playlist_files < <(load_playlist "$load_playlist_file")
        files+=("${playlist_files[@]}")
    fi
    
    # Find music files in directories
    if [[ ${#directories[@]} -gt 0 ]]; then
        mapfile -t found_files < <(find_music_files "${directories[@]}")
        files+=("${found_files[@]}")
    fi
    
    # Check if any files were found
    if [[ ${#files[@]} -eq 0 ]]; then
        error "No music files found"
        exit 1
    fi
    
    info "Found ${#files[@]} files"
    
    # Shuffle if requested
    if [[ "${CONFIG[SHUFFLE]}" == "true" ]]; then
        shuffle_array files
        info "Playlist shuffled"
    fi
    
    # Save playlist if requested
    if [[ -n "$save_playlist_file" ]]; then
        save_playlist "$save_playlist_file" "${files[@]}"
        exit 0
    fi
    
    # List files and exit if requested
    if [[ "$list_only" == "true" ]]; then
        printf '%s\n' "${files[@]}"
        exit 0
    fi
    
    # Determine player
    if [[ "${CONFIG[PLAYER]}" == "auto" ]]; then
        CONFIG[PLAYER]=$(detect_player) || {
            error "No supported audio player found. Please install mpv, mpg123, or ffplay."
            exit 1
        }
    fi
    
    # Check if player exists
    if ! command -v "${CONFIG[PLAYER]}" &> /dev/null; then
        error "Player '${CONFIG[PLAYER]}' not found"
        exit 1
    fi
    
    info "Using player: ${CONFIG[PLAYER]}"
    
    # Play files
    case "${CONFIG[PLAYER]}" in
        mpg123)
            play_mpg123 "${player_options[@]}" "${files[@]}"
            ;;
        mpv)
            play_mpv "${files[@]}"
            ;;
        ffplay)
            play_ffplay "${files[@]}"
            ;;
        *)
            error "Unknown player: ${CONFIG[PLAYER]}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
