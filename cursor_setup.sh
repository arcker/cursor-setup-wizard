#!/usr/bin/env bash

set -euo pipefail

# Constants
readonly SCRIPT_ALIAS_NAME="cursor-setup"
readonly APPIMAGES_DIR="$HOME/.local/bin/appimages"
readonly ICON_DIR="$HOME/.local/share/icons"
# USER_DESKTOP_FILE and CURSOR_WEBSITE will be used in future versions
readonly DOWNLOAD_URL="https://downloads.cursor.com/production/b6fb41b5f36bda05cab7109606e7404a65d1ff32/linux/x64/Cursor-0.47.9-x86_64.AppImage"
readonly ICON_URL="https://mintlify.s3-us-west-1.amazonaws.com/cursor/images/logo/app-logo.svg"
readonly VERSION_CHECK_TIMEOUT=20 # in seconds | if you have a slow connection, increase this value to 25, 30, or more
readonly SPINNERS=("meter" "line" "dot" "minidot" "jump" "pulse" "points" "globe" "moon" "monkey" "hamburger")
readonly SPINNER="${SPINNERS[0]}"
readonly DEPENDENCIES=("gum" "curl" "wget" "pv" "bc" "find:findutils" "chmod:coreutils" "timeout:coreutils" "mkdir:coreutils" "apparmor_parser:apparmor-utils" "dbus-launch:dbus-x11" "libfuse2")
readonly SYSTEM_DESKTOP_FILE="$HOME/.local/share/applications/cursor.desktop"
readonly APPARMOR_PROFILE="/etc/apparmor.d/cursor-appimage"
readonly RC_FILES=("bash:$HOME/.bashrc" "zsh:$HOME/.zshrc")
SCRIPT_PATH="$HOME/cursor-setup-wizard/cursor_setup.sh"
## Colors used for UI feedback and styling
readonly CLR_SCS="#16FF15"
readonly CLR_INF="#0095FF"
readonly CLR_BG="#131313"
readonly CLR_PRI="#6B30DA"
readonly CLR_ERR="#FB5854"
readonly CLR_WRN="#FFDA33"
readonly CLR_LGT="#F9F5E2"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2 # seconds
readonly BACKUP_DIR="$HOME/.cursor-setup-backups"
readonly MAX_BACKUPS=3

# Variables
sudo_pass=""

local_name=""
local_size=""
local_version=""
local_path=""
local_md5=""

remote_name=""
remote_size=""
remote_version=""
remote_md5=""

# Utility Functions
retry() {
  local cmd="$1"
  local retries="$MAX_RETRIES"
  local delay="$RETRY_DELAY"
  local attempt=1

  while [ $attempt -le $retries ]; do
    if eval "$cmd"; then
      return 0
    fi
    if [ $attempt -lt $retries ]; then
      logg warn "Attempt $attempt/$retries failed. Retrying in $delay seconds..."
      sleep "$delay"
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

validate_os() {
  local os_name
  spinner "Checking system compatibility..." "sleep 1"
  os_name=$(grep -i '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
  grep -iqE "ubuntu|kubuntu|xubuntu|lubuntu|pop!_os|elementary|zorin|linux mint" /etc/os-release || {
    logg error "$(printf "\n   This script is designed exclusively for Ubuntu and its popular derivatives.\n   Detected: %s. \n   Exiting..." "$os_name")"; exit 1
  }
  logg success "$(echo -e "Detected $os_name (Ubuntu or derivative). System is compatible.")"
}

install_script_alias() {
  local alias_command="alias ${SCRIPT_ALIAS_NAME}=\"$SCRIPT_PATH\"" 
  local alias_added=false
  
  for entry in "${RC_FILES[@]}"; do
    local shell_name="${entry%%:*}" 
    local rc_file="${entry#*:}"
    
    if [[ -f "$rc_file" ]]; then
      # Add AppImages directory to PATH
      if ! grep -q "export PATH=\"\$PATH:$APPIMAGES_DIR\"" "$rc_file"; then
        echo -e "\n# Add AppImages directory to PATH\nexport PATH=\"\$PATH:$APPIMAGES_DIR\"" >> "$rc_file"
      fi
      
      # Add alias
      if ! grep -Fxq "$alias_command" "$rc_file"; then
        echo -e "\n\n# This alias runs the Cursor Setup Wizard, simplifying installation and configuration.\n# For more details, visit: https://github.com/jorcelinojunior/cursor-setup-wizard\n$alias_command\n" >>"$rc_file"
        alias_added=true
        if [[ "$(basename "$SHELL")" == "$shell_name" ]]; then
          echo " 🏷️  Adding the alias \"${SCRIPT_ALIAS_NAME}\" to the current shell..."
          $(basename "$SHELL") -c "source $rc_file"
        fi
      fi
    fi
  done
  
  if [[ "$alias_added" == true ]]; then
    echo -e "\n   # The alias \"${SCRIPT_ALIAS_NAME}\" has been successfully added! ✨"
    echo "   # Open a new terminal to run the script \"Cursor Setup Wizard\""
    echo "   # using the following command:"
    echo "     ╭────────────────────╮"
    echo "     │  $ ${SCRIPT_ALIAS_NAME}    │"
    echo "     ╰────────────────────╯"
    echo ""
    read -rp "   Press any key to close this terminal..." -n1
    kill -9 $PPID
  else
    logg success "The alias '${SCRIPT_ALIAS_NAME}' is already configured. No changes were made."
  fi
}

check_and_install_dependencies() {
  spinner "Checking dependencies..." "sleep 1"
  local missing_packages=()
  for dep_info in "${DEPENDENCIES[@]}"; do
    local dep="${dep_info%%:*}" package="${dep_info#*:}"
    [[ "$package" == "$dep" ]] && package=""
    command -v "$dep" >/dev/null 2>&1 || missing_packages+=("${package:-$dep}")
  done

  if [[ "${#missing_packages[@]}" -gt 0 ]]; then
    logg prompt "Installing: ${missing_packages[*]}"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    if [[ "${VERBOSE:-false}" == "true" ]]; then
      sudo apt update -y && sudo apt install -y "${missing_packages[@]}"
    else
      sudo apt update -y >/dev/null 2>&1 && sudo apt install -y "${missing_packages[@]}" >/dev/null 2>&1
    fi
  fi
  logg success "All dependencies are good to go!"
}

show_banner() { clear; gum style --border double --border-foreground="$CLR_PRI" --margin "1 0 2 2" --padding "1 3" --align center --foreground="$CLR_LGT" --background="$CLR_BG" "$(echo -e "🧙 Welcome to the Cursor Setup Wizard! 🎉\n 📡 Effortlessly fetch, download, and configure Cursor. 🔧")"; }

show_balloon() { gum style --border double --border-foreground="$CLR_PRI" --margin "1 2" --padding "1 1" --align center --foreground="$CLR_LGT" "$1"; }

nostyle() {
  echo "$1" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

edit_this_script() {
  local editors=("cursor:CursorAi" "code:Visual Studio Code" "gedit:Gedit" "nano:Nano")
  spinner "Opening the script in your default editor..." "sleep 2"
  for e in "${editors[@]}"; do
    local cmd="${e%%:*}" name="${e#*:}"
    command -v "$cmd" >/dev/null 2>&1 && { logg success "$(echo -e "\n    The script is now open in $name. Make your changes and save the file.\n    Remember to close the current script and reopen it with the \n    command 'cursor-setup' to see your changes.")"; "$cmd" "$SCRIPT_PATH"; return 0; }
  done
  logg error "No suitable editor found to open the script."; return 1
}

extract_version() {
  [[ "$1" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && { echo "${BASH_REMATCH[1]}"; return 0; }
  echo "Error: No version found in filename" >&2; return 1
}

convert_to_mb() {
  local size="$1"
  # Replace comma with dot for calculation
  size=$(echo "$size" | tr ',' '.')
  # Use awk for formatting
  awk "BEGIN { printf \"%.2f MB\", $size / 1048576 }"
}

spinner() {
  local title="$1" command="$2" chars="|/-\\" i=0
  command -v gum >/dev/null 2>&1 && gum spin --spinner "$SPINNER" --spinner.foreground="$CLR_SCS" --title "$(gum style --bold "$title")" -- bash -c "$command" || {
    printf "%s " "$title"; bash -c "$command" & local pid=$!
    while kill -0 $pid 2>/dev/null; do printf "\r%s %c" "$title" "${chars:i++%${#chars}}"; sleep 0.1; done
    printf "\r\033[K"
  }
}

sudo_please() {
  while true; do
    [[ -z "$sudo_pass" ]] && sudo_pass=$(gum input --password --placeholder "Please enter your 'sudo' password: " --header=" 🛡️  Let's keep things secure. " --header.foreground="$CLR_LGT" --header.background="$CLR_PRI" --header.margin="1 0 1 2" --header.align="center" --cursor.background="$CLR_LGT" --cursor.foreground="$CLR_PRI" --prompt="🗝️  ")
    echo "$sudo_pass" | sudo -S -k true >/dev/null 2>&1 && break
    logg error "Oops! The password was incorrect. Try again."; sudo_pass=""
  done
}

logg() {
  local TYPE="$1" MSG="$2"
  local SYMBOL="" COLOR="" LABEL="" BGCOLOR="" FG=""
  GUM_AVAILABLE=$(command -v gum >/dev/null && echo true || echo false)
  case "$TYPE" in
    error) SYMBOL="$(echo -e "\n ✖")"; COLOR="$CLR_ERR"; LABEL=" ERROR "; BGCOLOR="$CLR_ERR"; FG="--foreground=$CLR_BG" ;;
    info) SYMBOL=" »"; COLOR="$CLR_INF" ;;
    md) command -v glow >/dev/null && glow "$MSG" || cat "$MSG"; return ;;
    prompt) SYMBOL=" ▶"; COLOR="$CLR_PRI" ;;
    star) SYMBOL=" ◆"; COLOR="$CLR_WRN" ;;
    start|success) SYMBOL=" ✔"; COLOR="$CLR_SCS" ;;
    warn) SYMBOL="$(echo -e "\n ◆")"; COLOR="$CLR_WRN"; LABEL=" WARNING "; BGCOLOR="$CLR_WRN"; FG="--foreground=$CLR_BG" ;;
    *) echo "$MSG"; return ;;
  esac
  { $GUM_AVAILABLE && gum style "$(gum style --foreground="$COLOR" "$SYMBOL") $(gum style --bold ${BGCOLOR:+--background="$BGCOLOR"} ${FG:-} "${LABEL:-}") $(gum style "$MSG")"; } || { echo "${TYPE^^}: $MSG"; }
  return 0
}

fetch_remote_version() {
  logg prompt "Looking for the latest version online..."
  
  # Version extracted directly from URL
  remote_version="0.47.9"
  remote_name="Cursor-${remote_version}-x86_64.AppImage"
  
  # Get file information
  headers=$(spinner "Fetching version info from the server..." \
    "sleep 1 && timeout \"$VERSION_CHECK_TIMEOUT\" wget -S \"$DOWNLOAD_URL\" -q -O /dev/null 2>&1 || true")
  
  if [[ -z "$headers" ]]; then
    logg error "$(echo -e "Failed to fetch headers from the server.\n   • Ensure your internet connection is active and stable.\n   • Ensure that 'VERSION_CHECK_TIMEOUT' ($VERSION_CHECK_TIMEOUT sec) is set high enough to retrieve the headers.\n   • Also, verify if 'DOWNLOAD_URL' is correct: $DOWNLOAD_URL.\n\n ")"
    return 1
  fi
  
  logg success "Latest version details retrieved successfully."
  remote_size=$(echo "$headers" | grep -oE 'Content-Length: [0-9]+' | sed 's/Content-Length: //') || remote_size="0"
  remote_md5=$(echo "$headers" | grep -oE 'ETag: "[^"]+"' | sed 's/ETag: //; s/"//g' || echo "unknown")
  
  logg info "$(echo -e "Latest version online:\n      - name: $remote_name\n      - version: $remote_version\n      - size: $(convert_to_mb "$remote_size")\n      - MD5 Hash: $remote_md5\n      - URL: $DOWNLOAD_URL\n")"
}

find_local_version() {
  show_log=${1:-false}
  [[ $show_log == true ]] && spinner "Searching for a local version..." "sleep 2;"
  mkdir -p "$APPIMAGES_DIR"
  local_path=$(find "$APPIMAGES_DIR" -maxdepth 1 -type f -name 'cursor-*.AppImage' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
  if [[ -n "$local_path" ]]; then
    local_name=$(basename "$local_path")
    local_size=$(stat -c %s "$local_path" 2>/dev/null || echo "0")
    local_version=$(extract_version "$local_path")
    local_md5=$(md5sum "$local_path" | cut -d' ' -f1)
    [[ $show_log == true ]] && logg info "$(printf "Local version found:\n      - name: %s\n      - version: %s\n      - size: %s\n      - MD5 Hash: %s\n      - path: %s\n" "$local_name" "$local_version" "$(convert_to_mb "$local_size")" "$local_md5" "$local_path")"
    return 0
  fi
  [[ $show_log == true ]] && logg error "$(echo -e "No local version found in $APPIMAGES_DIR\n   Go back to the menu and fetch it first.")"
  return 1
}

download_logo() {
  logg prompt "Getting the Cursor logo ready..."
  mkdir -p "$ICON_DIR"
  
  if ! retry "curl -s -o \"$ICON_DIR/cursor-icon.svg\" \"$ICON_URL\""; then
    logg error "Failed to download the logo after $MAX_RETRIES attempts. Please check your connection."
    return 1
  fi
  
  if [[ ! -s "$ICON_DIR/cursor-icon.svg" ]]; then
    logg error "The downloaded logo file is empty. Please check the download URL and try again."
    return 1
  fi
  
  logg success "Logo successfully downloaded to: $ICON_DIR/cursor-icon.svg"
  return 0
}

verify_appimage() {
  local appimage_path="$1"
  logg prompt "Verifying AppImage..."

  # Check if file exists
  if [ ! -f "$appimage_path" ]; then
    logg error "AppImage does not exist: $appimage_path"
    return 1
  fi

  # Check if file is executable
  if [ ! -x "$appimage_path" ]; then
    logg error "AppImage is not executable: $appimage_path"
    return 1
  fi

  # Check minimum size (100MB)
  local min_size=$((100 * 1024 * 1024))
  local file_size
  file_size=$(stat -c%s "$appimage_path")
  if [ "$file_size" -lt "$min_size" ]; then
    logg error "AppImage is too small: $(convert_to_mb "$file_size") (minimum expected: 100MB)"
    return 1
  fi

  # Check if it's a valid AppImage
  if ! file "$appimage_path" | grep -q "ELF.*executable"; then
    logg error "File is not a valid AppImage"
    return 1
  fi

  # Check required dependencies
  local missing_libs
  missing_libs=$(ldd "$appimage_path" 2>/dev/null | grep "not found" || true)
  if [ -n "$missing_libs" ]; then
    logg error "Missing libraries:"
    if [[ "${VERBOSE:-false}" == "true" ]]; then
      echo "$missing_libs" | while read -r line; do
        logg error "  $line"
      done
    else
      logg error "  Run with --verbose to see details"
    fi
    return 1
  fi

  # Check if AppImage can be extracted (without actually running it)
  if ! "$appimage_path" --appimage-extract --help >/dev/null 2>&1; then
    logg error "AppImage cannot be extracted"
    return 1
  fi

  logg success "AppImage verification completed successfully"
  return 0
}

download_appimage() {
  logg prompt "Starting the download of the latest version..."
  local output_document="$APPIMAGES_DIR/$remote_name"
  
  # Create AppImages directory if it doesn't exist
  mkdir -p "$APPIMAGES_DIR"
  
  # Clean up old versions
  find "$APPIMAGES_DIR" -maxdepth 1 -type f -name 'cursor-*.AppImage' ! -name "$remote_name" -delete 2>/dev/null || true
  
  # Use wget with improved options for download and retry
  local wget_opts="--trust-server-names --content-disposition --output-document=\"$output_document\""
  if [[ "${VERBOSE:-false}" == "true" ]]; then
    wget_opts="$wget_opts --progress=bar:force --show-progress"
  else
    wget_opts="$wget_opts --progress=bar:noscroll --no-verbose"
  fi
  
  if ! retry "wget $wget_opts \"$DOWNLOAD_URL\""; then
    logg error "AppImage download failed after $MAX_RETRIES attempts. Please check your connection and try again."
    return 1
  fi
  
  # Add execute permissions to the downloaded AppImage
  if ! retry "chmod +x \"$output_document\""; then
    logg error "Failed to set execute permissions on the AppImage"
    rm -f "$output_document"
    return 1
  fi
  
  # Verify AppImage after download
  if ! verify_appimage "$output_document"; then
    logg error "The downloaded AppImage is not valid"
    rm -f "$output_document"
    return 1
  fi
  
  local_path="$output_document"
  logg success "Download complete, and AppImage verified!"
}

setup_launchers() {
  local error=false
  logg prompt "Creating desktop launchers for Cursor..."
  
  # Clean up old .desktop files
  rm -f ~/.local/share/applications/cursor.desktop
  rm -f /usr/share/applications/cursor.desktop
  
  # Create Desktop directory if it doesn't exist
  if [[ ! -d "$HOME/Desktop" ]]; then
    logg info "Creating Desktop directory..."
    mkdir -p "$HOME/Desktop"
  fi

  # Create applications directory if it doesn't exist
  mkdir -p "$(dirname "$SYSTEM_DESKTOP_FILE")"

  # Create a direct symbolic link to the AppImage on the desktop
  if ! retry "ln -sf \"$local_path\" \"$HOME/Desktop/Cursor\""; then
    logg error "Failed to create direct AppImage link on desktop"
    error=true
  else
    logg success "Created direct AppImage link on desktop"
  fi

  # Create .desktop file for application menu
  if ! retry "echo '[Desktop Entry]
Type=Application
Name=Cursor
GenericName=Intelligent, fast, and familiar, Cursor is the best way to code with AI.
Exec=\"$local_path\" --no-sandbox %F
Icon=$ICON_DIR/cursor-icon.svg
X-AppImage-Version=$local_version
Categories=Utility;Development
StartupWMClass=Cursor
Terminal=false
Comment=Cursor is an AI-first coding environment for software development.
Keywords=cursor;ai;code;editor;ide;artificial;intelligence;learning;programming;developer;development;software;engineering;productivity;vscode;sublime;coding;gpt;openai;copilot;
MimeType=x-scheme-handler/cursor;
DBusActivatable=true
StartupNotify=true' > \"$SYSTEM_DESKTOP_FILE\""; then
    logg error "Failed to create application menu entry"
    error=true
  else
    logg success "Created application menu entry"
    
    if ! retry "chmod +x \"$SYSTEM_DESKTOP_FILE\""; then
      logg error "Failed to set permissions for menu entry"
      error=true
    fi
  fi

  # Update application cache with sudo
  sudo_please
  if ! retry "sudo -S <<< \"$sudo_pass\" update-desktop-database"; then
    logg error "Failed to update desktop database"
    error=true
  fi

  # Force GTK icon cache update
  if ! retry "gtk-update-icon-cache -f -t ~/.local/share/icons"; then
    logg error "Failed to update icon cache"
    error=true
  fi

  # Clean application cache
  if ! retry "rm -rf ~/.cache/applications/*"; then
    logg error "Failed to clear application cache"
    error=true
  fi
  
  if [ "$error" = false ]; then
    logg success "All launchers created successfully!"
    logg info "$(echo -e "You can now launch Cursor in several ways:\n  1. Double-click the Cursor icon on the desktop\n  2. Via the application menu\n  3. From the command line: $local_path\n  4. Using the 'cursor' command in the terminal\n\nIf the application doesn't start, try:\n  1. Pin the application to the dock\n  2. Restart your session\n  3. Check if libfuse2 is installed: sudo apt install libfuse2")"
    return 0
  else
    logg warn "Some launchers could not be created. Please check the error messages above."
    return 1
  fi
}

configure_apparmor() {
  logg prompt "Setting up AppArmor configuration..."
  sudo_please
  
  if ! retry "systemctl is-active --quiet apparmor"; then
    logg warn "AppArmor is not active. Enabling and starting the service..."
    if ! retry "sudo -S <<< \"$sudo_pass\" systemctl enable apparmor && sudo -S <<< \"$sudo_pass\" systemctl start apparmor"; then
      logg error "Failed to start AppArmor service after $MAX_RETRIES attempts"
      return 1
    fi
    logg success "AppArmor service started and enabled."
  fi

  local profile_content="abi <abi/4.0>,
include <tunables/global>

profile cursor \"$local_path\" flags=(unconfined) {
  userns,
  include if exists <local/cursor>
}"

  if ! retry "sudo -S <<< \"$sudo_pass\" bash -c 'printf \"%s\" \"$profile_content\" > \"$APPARMOR_PROFILE\"'"; then
    logg error "Failed to create AppArmor profile after $MAX_RETRIES attempts"
    return 1
  fi

  if ! retry "sudo -S <<< \"$sudo_pass\" apparmor_parser -r \"$APPARMOR_PROFILE\""; then
    logg error "Failed to apply AppArmor profile after $MAX_RETRIES attempts"
    return 1
  fi
  
  logg success "AppArmor profile successfully applied!"
  return 0
}

add_cli_command() {
  logg prompt "Adding the 'cursor' command to your system..."
  sudo_please

  # Créer un fichier temporaire pour le script
  local temp_script
  temp_script=$(mktemp)
  
  # Écrire le contenu du script dans le fichier temporaire
  cat > "$temp_script" << 'EOF'
#!/bin/bash

APPIMAGE_PATH="$1"

if [ ! -f "$APPIMAGE_PATH" ]; then
   echo "Error: Cursor AppImage not found at $APPIMAGE_PATH" >&2
   exit 1
fi

# Vérifier si libfuse2 est installé
if ! dpkg -l | grep -q "^ii.*libfuse2"; then
   echo "Error: libfuse2 is not installed. Please run: sudo apt install libfuse2" >&2
   exit 1
fi

# Exécuter l'AppImage avec les options appropriées
"$APPIMAGE_PATH" --no-sandbox "$@" &> /dev/null &
EOF

  # Remplacer le chemin de l'AppImage dans le script
  sed -i "s|APPIMAGE_PATH=\"\$1\"|APPIMAGE_PATH=\"$local_path\"|" "$temp_script"

  # Copier le script dans /usr/local/bin
  if ! retry "sudo -S <<< \"$sudo_pass\" cp \"$temp_script\" /usr/local/bin/cursor"; then
    logg error "Failed to create CLI command after $MAX_RETRIES attempts"
    rm -f "$temp_script"
    return 1
  fi

  # Nettoyer le fichier temporaire
  rm -f "$temp_script"

  if ! retry "sudo -S <<< \"$sudo_pass\" chmod +x /usr/local/bin/cursor"; then
    logg error "Failed to set permissions for CLI command after $MAX_RETRIES attempts"
    return 1
  fi

  logg success "Permissions updated for '/usr/local/bin/cursor'."
  logg success "$(printf "The 'cursor' command is now ready to use! ✨\n    Here are a few ways to use it:\n      $ cursor                  # Open the Cursor application\n      $ cursor .                # Open the current directory in Cursor\n      $ cursor /some/directory  # Open a specific directory in Cursor\n      $ cursor /path/to/file.py # Open a specific file in Cursor\n")"
  return 0
}

create_desktop_launcher() {
  logg prompt "Creating desktop launcher..."
  sudo_please

  # Créer le fichier .desktop avec des options supplémentaires
  local desktop_content="[Desktop Entry]
Type=Application
Name=Cursor
GenericName=Intelligent, fast, and familiar, Cursor is the best way to code with AI.
Exec=env DISABLE_VTE=1 \"$local_path\" --no-sandbox %F
Icon=$ICON_DIR/cursor-icon.svg
X-AppImage-Version=
Categories=Utility;Development
StartupWMClass=Cursor
Terminal=false
Comment=Cursor is an AI-first coding environment for software development.
Keywords=cursor;ai;code;editor;ide;artificial;intelligence;learning;programming;developer;development;software;engineering;productivity;vscode;sublime;coding;gpt;openai;copilot;
MimeType=x-scheme-handler/cursor;
DBusActivatable=true
StartupNotify=true"

  if ! retry "sudo -S <<< \"$sudo_pass\" bash -c 'printf \"%s\" \"$desktop_content\" > /usr/share/applications/cursor.desktop'"; then
    logg error "Failed to create desktop launcher after $MAX_RETRIES attempts"
    return 1
  fi

  if ! retry "sudo -S <<< \"$sudo_pass\" chmod +x /usr/share/applications/cursor.desktop"; then
    logg error "Failed to set permissions for desktop launcher after $MAX_RETRIES attempts"
    return 1
  fi

  # Créer aussi une copie locale pour l'utilisateur
  if ! retry "mkdir -p ~/.local/share/applications && cp /usr/share/applications/cursor.desktop ~/.local/share/applications/"; then
    logg error "Failed to create local desktop launcher"
    return 1
  fi

  if ! retry "chmod +x ~/.local/share/applications/cursor.desktop"; then
    logg error "Failed to set permissions for local desktop launcher"
    return 1
  fi

  # Mettre à jour la base de données des applications
  if ! retry "update-desktop-database"; then
    logg error "Failed to update desktop database"
    return 1
  fi

  logg success "Desktop launcher created successfully."
  return 0
}

check_environment() {
  logg prompt "Checking system environment..."
  
  # Check available disk space
  local required_space=500 # MB
  local available_space
  available_space=$(df -m "${HOME:?}" | awk 'NR==2 {print $4}')
  if [ "$available_space" -lt "$required_space" ]; then
    logg error "Insufficient disk space. Required: ${required_space}MB, Available: ${available_space}MB"
    return 1
  fi

  # Check available memory
  local required_memory=2048 # MB
  local available_memory
  available_memory=$(free -m | awk '/^Mem:/{print $7}')
  if [ "$available_memory" -lt "$required_memory" ]; then
    logg warn "Low available memory. Recommended: ${required_memory}MB, Available: ${available_memory}MB"
  fi

  # Check critical directory permissions
  local critical_dirs=(
    "${HOME:?}/.local/bin"
    "${HOME:?}/.local/share"
    "${HOME:?}/.local/share/applications"
    "${HOME:?}/.local/share/icons"
    "${APPIMAGES_DIR:?}"
  )

  for dir in "${critical_dirs[@]}"; do
    if ! mkdir -p "$dir" 2>/dev/null; then
      logg error "Cannot create/access directory: $dir"
      return 1
    fi
    if ! [ -w "$dir" ]; then
      logg error "No write permission on: $dir"
      return 1
    fi
  done

  # Check internet connection
  if ! ping -c 1 -W 5 downloads.cursor.com >/dev/null 2>&1; then
    logg error "No connection to downloads.cursor.com. Please check your internet connection."
    return 1
  fi

  # Check critical system dependencies
  local critical_deps=("libfuse2" "libgtk-3-0" "libnotify4" "libnss3" "libxss1" "libxtst6")
  local missing_deps=()
  
  for dep in "${critical_deps[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$dep"; then
      missing_deps+=("$dep")
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    logg prompt "Installing missing system dependencies: ${missing_deps[*]}"
    sudo_please
    if ! retry "sudo -S <<< \"$sudo_pass\" apt-get install -y ${missing_deps[*]}"; then
      logg error "Failed to install system dependencies"
      return 1
    fi
  fi

  # Check environment variables
  if [ -z "${DISPLAY:-}" ]; then
    logg warn "DISPLAY variable not set. This might affect some GUI features."
    logg info "If you're running this in a terminal-only environment, you can continue."
    logg info "If you're running this in a graphical environment, please ensure DISPLAY is set."
  fi

  # Check filesystem
  if ! mount | grep -q "noexec.*/tmp"; then
    logg warn "The /tmp directory is not mounted with noexec. This may pose security issues."
  fi

  logg success "System environment check completed successfully"
  return 0
}

cleanup() {
  local exit_code=$?
  local error_msg="$1"
  
  logg warn "Cleaning up..."
  
  # Remove temporary files
  rm -f /tmp/cursor-*.AppImage 2>/dev/null
  rm -f /tmp/cursor-setup-*.log 2>/dev/null
  
  # Remove partial files
  find "$APPIMAGES_DIR" -name "*.part" -delete 2>/dev/null
  
  # Remove invalid .desktop files
  rm -f ~/.local/share/applications/cursor.desktop.invalid 2>/dev/null
  rm -f /usr/share/applications/cursor.desktop.invalid 2>/dev/null
  
  if [ "$exit_code" -ne 0 ]; then
    logg error "An error occurred: $error_msg"
    logg info "You can try to restore a previous version with:"
    logg info "  ./cursor_setup.sh --restore"
  fi
  
  return "$exit_code"
}

create_backup() {
  local backup_name
  backup_name="cursor-setup-$(date +%Y%m%d-%H%M%S)"
  local backup_path
  backup_path="$BACKUP_DIR/$backup_name"
  
  mkdir -p "$BACKUP_DIR"
  
  # Create backup of important files
  {
    # Backup AppImage
    if [ -f "$local_path" ]; then
      mkdir -p "$backup_path/appimages"
      cp "$local_path" "$backup_path/appimages/"
    fi
    
    # Backup .desktop files
    if [ -f ~/.local/share/applications/cursor.desktop ]; then
      mkdir -p "$backup_path/desktop"
      cp ~/.local/share/applications/cursor.desktop "$backup_path/desktop/"
    fi
    
    # Backup icon
    if [ -f "$ICON_DIR/cursor-icon.svg" ]; then
      mkdir -p "$backup_path/icons"
      cp "$ICON_DIR/cursor-icon.svg" "$backup_path/icons/"
    fi
    
    # Backup AppArmor configuration
    if [ -f "$APPARMOR_PROFILE" ]; then
      mkdir -p "$backup_path/apparmor"
      cp "$APPARMOR_PROFILE" "$backup_path/apparmor/"
    fi
    
    # Create metadata file
    echo "Backup created at: $(date)" > "$backup_path/metadata.txt"
    echo "Cursor version: $local_version" >> "$backup_path/metadata.txt"
    echo "AppImage path: $local_path" >> "$backup_path/metadata.txt"
    
  } 2>/dev/null || true
  
  # Remove old backups
  ls -t "$BACKUP_DIR" | tail -n +$((MAX_BACKUPS + 1)) | while read -r old_backup; do
    rm -rf "$BACKUP_DIR/$old_backup"
  done
}

restore_backup() {
  local backups
  mapfile -t backups < <(find "${BACKUP_DIR:?}" -maxdepth 1 -type d -name 'cursor-setup-*' 2>/dev/null | sort -r)
  
  if [ ${#backups[@]} -eq 0 ]; then
    logg error "No backups found"
    return 1
  fi
  
  logg prompt "Available backups:"
  for i in "${!backups[@]}"; do
    echo "$((i+1)). ${backups[$i]}"
  done
  
  read -rp "Choose a backup to restore (1-${#backups[@]}): " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
    logg error "Invalid choice"
    return 1
  fi
  
  local selected_backup
  selected_backup="${BACKUP_DIR:?}/${backups[$((choice-1))]}"
  
  # Restore files
  {
    # Restore AppImage
    if [ -d "$selected_backup/appimages" ]; then
      cp "$selected_backup/appimages/"* "$APPIMAGES_DIR/"
    fi
    
    # Restore .desktop files
    if [ -d "$selected_backup/desktop" ]; then
      cp "$selected_backup/desktop/"* ~/.local/share/applications/
    fi
    
    # Restore icon
    if [ -d "$selected_backup/icons" ]; then
      cp "$selected_backup/icons/"* "$ICON_DIR/"
    fi
    
    # Restore AppArmor configuration
    if [ -d "$selected_backup/apparmor" ]; then
      sudo_please
      sudo -S <<< "$sudo_pass" cp "$selected_backup/apparmor/"* "$APPARMOR_PROFILE"
    fi
    
  } 2>/dev/null || true
  
  logg success "Backup restored successfully"
  return 0
}

menu() {
  local option
  show_banner
  while true; do
    all_in_one=$(gum style --foreground="$CLR_LGT" --bold "All-in-One (fetch, download & configure all)")
    reconfigure_all=$(gum style --foreground="$CLR_LGT" --bold "Reconfigure All (no online fetch)")
    setup_apparmor=$(gum style --foreground="$CLR_LGT" --bold "Setup AppArmor Profile")
    add_cli_command=$(gum style --foreground="$CLR_LGT" --bold "Add 'cursor' CLI Command (bash/zsh)")
    edit_script=$(gum style --foreground="$CLR_LGT" --bold "Edit This Script")
    _exit=$(gum style --foreground="$CLR_LGT" --italic "Exit")
    option=$(echo -e "$all_in_one\n$reconfigure_all\n$setup_apparmor\n$add_cli_command\n$edit_script\n$_exit" | gum choose --header "🧙 Pick what you'd like to do next:" --header.margin="0 0 0 2" --header.border="rounded" --header.padding="0 2 0 2" --header.italic --header.foreground="$CLR_LGT" --cursor=" ➤ " --cursor.foreground="$CLR_ERR" --cursor.background="$CLR_PRI" --selected.foreground="$CLR_LGT" --selected.background="$CLR_PRI")
    case "$option" in
      "$(nostyle "$all_in_one")")
        fetch_remote_version
        if ! find_local_version || [[ "$local_md5" != "$remote_md5" ]]; then
          download_appimage
          download_logo
          setup_launchers
          configure_apparmor
          add_cli_command
        else
          find_local_version true
          show_balloon "$(echo -e "🧙 The latest version is already installed and ready to use! 🎈\n🌟 Ready to start coding? Let's build something amazing! 💻")"
        fi
        ;;
      "$(nostyle "$reconfigure_all")")
        if find_local_version true; then
          download_logo
          setup_launchers
          configure_apparmor
          add_cli_command
        fi
        ;;
      "$(nostyle "$setup_apparmor")")
        if find_local_version true; then
          configure_apparmor
        fi
        ;;
      "$(nostyle "$add_cli_command")")
        if find_local_version true; then
          add_cli_command
        fi
        ;;
      "$(nostyle "$edit_script")")
        edit_this_script
        ;;
      "$(nostyle "$_exit")")
          if gum confirm "Are you sure you want to exit?" --show-help --prompt.foreground="$CLR_WRN" --selected.background="$CLR_PRI"; then
            clear;
            gum style --border double --border-foreground="$CLR_PRI" --padding "1 3" --margin "1 2" --align center --background "$CLR_BG" --foreground "$CLR_LGT" "$(echo -e "🎩🪄 Thanks for stopping by! Happy coding with Cursor!\n\n Enjoyed this tool? Support it and keep the magic alive!\n☕ Buy me a coffee 🤗\n $(gum style  --foreground="$CLR_WRN" "https://buymeacoffee.com/jorcelinojunior") \n\n Your kindness helps improve this tool for everyone!\n Thank you for your support! 🌻💜 ")"
            echo -e " \n\n "
            break
          fi
        ;;
    esac
    if gum confirm "$(echo -e "\nWould you like to do something else?" | gum style --foreground="$CLR_PRI")" --affirmative="《Back" --negative="✖ Close" --show-help --prompt.foreground="$CLR_WRN" --selected.background="$CLR_PRI"; then
      show_banner
    else
      break
    fi
  done
}

main() {
  clear
  echo ""
  
  # Get the actual script path
  SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
  
  # Handle command line arguments
  VERBOSE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose)
        VERBOSE=true
        shift
        ;;
      --restore)
        restore_backup
        return
        ;;
      --install)
        INSTALL=true
        shift
        ;;
      *)
        logg error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  
  # Add exit handler
  trap 'cleanup "An unexpected error occurred"' EXIT
  
  # Check environment
  if ! check_environment; then
    logg error "System environment does not meet minimum requirements."
    exit 1
  fi
  
  validate_os
  check_and_install_dependencies
  
  # If --install argument is provided, start installation directly
  if [[ "${INSTALL:-false}" == "true" ]]; then
    fetch_remote_version
    if ! find_local_version || [[ "$local_md5" != "$remote_md5" ]]; then
      download_appimage
      download_logo
      setup_launchers
      configure_apparmor
      add_cli_command
      create_backup
      show_balloon "$(echo -e "🧙 Installation completed successfully! 🎈\n🌟 You can now launch Cursor! 💻")"
    else
      find_local_version true
      show_balloon "$(echo -e "🧙 The latest version is already installed and ready to use! 🎈\n🌟 Ready to code? Let's create something amazing! 💻")"
    fi
    return
  fi
  
  # Otherwise, continue with normal menu
  install_script_alias
  spinner "Initializing the setup wizard..." "sleep 1"
  menu
}

main "$@"
