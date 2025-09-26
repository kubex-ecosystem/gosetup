#!/usr/bin/env bash

# Go Setup Script - Installs, updates, or removes Go.
# Refactored for robustness and POSIX compatibility.

set -eo pipefail

# shellcheck disable=SC2016

_main_args=("$@")

# Create a temporary directory for downloads and ensure it's cleaned up on exit.
TMP_DIR=$(mktemp -d -t go-installer-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

function tpt {
  if ! tty -s &>/dev/null; then
    return
  fi
  if ! command -v tpt &>/dev/null; then
    return
  fi
  command tpt "$@" 2>/dev/null || true
}
export -f tpt

# Color definitions for tpt
#BLACK=0
RED=1
GREEN=2
YELLOW=3
BLUE=4
CYAN=6
RESET=$(tpt sgr0)
TEXT_COLOR="tpt setaf "
# BACKGROUND_COLOR="tpt setab "
# CLEAR_UP="#tpt cuu 1; tpt ed;"

# --- Utility Functions ---

function get_download_command() {
  if command -v curl &>/dev/null; then
    echo "curl --fail --silent --location"
  elif command -v wget &>/dev/null; then
    echo "wget --quiet --output-document=-"
  else
    echo "$($TEXT_COLOR $RED)Error: Neither curl nor wget is available. Please install one of them.${RESET}" >&2
    exit 1
  fi
}

function what_platform() {
  local os
  os="$(uname -s)"
  local arch
  arch="$(uname -m)"

  case "$os" in
  "Linux")
    case "$arch" in
    "x86_64") arch="amd64" ;;
    "armv6") arch="armv6l" ;;
    "armv8" | "aarch64") arch="arm64" ;;
    .*386.*) arch="386" ;;
    esac
    platform="linux-$arch"
    ;;
  "Darwin")
    case "$arch" in
    "x86_64") arch="amd64" ;;
    "arm64") arch="arm64" ;;
    esac
    platform="darwin-$arch"
    ;;
  "MINGW" | "MSYS" | "CYGWIN")
    case "$arch" in
    "x86_64") arch="amd64" ;;
    "arm64") arch="arm64" ;;
    esac
    platform="windows-$arch"
    ;;
  *)
    echo "$($TEXT_COLOR $RED)Error: Unsupported operating system '$os'.${RESET}" >&2
    exit 1
    ;;
  esac
  echo "$platform"
}

function what_shell_profile() {
  local current_shell
  current_shell="${SHELL:-$(ps -p $$ | awk 'NR>1{print $4}')}"
  current_shell_name=$(basename "$current_shell")

  case "$current_shell_name" in
  "zsh") echo "$HOME/.zshrc" ;;
  "bash")
    if [[ -f "$HOME/.bashrc" ]]; then
      echo "$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      echo "$HOME/.bash_profile"
    else
      # Default for non-login interactive shells on macOS
      echo "$HOME/.bashrc"
    fi
    ;;
  "fish") echo "$HOME/.config/fish/config.fish" ;;
  *)
    echo "$($TEXT_COLOR $RED)Could not detect shell profile for '$current_shell_name'.${RESET}" >&2
    echo "Please add the following lines to your shell profile manually:" >&2
    echo "export GOROOT=\$HOME/.go" >&2
    echo "export GOPATH=\$HOME/go" >&2
    echo "export PATH=\$PATH:\$GOROOT/bin:\$GOPATH/bin" >&2
    return 1
    ;;
  esac
}

function what_installed_version() {
  go version 2>/dev/null | sed -n 's/.*go\([0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?\).*/\1/p' || echo ""
}

# --- Core Logic Functions ---

function find_version_info() {
  local version_to_find="$1"
  local platform="$2"
  local download_cmd

  download_cmd=$(get_download_command)
  local go_api_url="https://go.dev/dl/?mode=json"

  >&2 echo "Fetching available Go versions for $platform..."
  local versions_json
  versions_json=$($download_cmd "$go_api_url")
  if [[ -z "$versions_json" ]]; then
    >&2 echo "$($TEXT_COLOR $RED)Error: Failed to fetch Go versions from API.${RESET}"
    exit 1
  fi

  local version_filter
  if [[ "$version_to_find" == "latest" ]]; then
    version_filter='.[0]' # The first entry is the latest stable
  else
    # Match specific version, e.g., "1.21.5" or "1.21" (will find latest patch)
    version_filter=".[] | select(.version | startswith(\"go$version_to_find\"))"
  fi

  local file_filter=""
  file_filter=".files[] | select(.os == \"$(echo "$platform" | cut -d- -f1)\" and .arch == \"$(echo "$platform" | cut -d- -f2)\" and .kind == \"archive\")"

  if ! command -v jq &>/dev/null; then
    >&2 echo "$($TEXT_COLOR $RED)Error: 'jq' is required but not installed. Please install it to continue.${RESET}"
    exit 1
  fi

  local version_info
  version_info=$(echo "$versions_json" | jq -r "($version_filter | $file_filter) | .filename + \" \" + .sha256 + \" \" + .version")

  if [[ -z "$version_info" ]]; then
    >&2 echo "$($TEXT_COLOR $RED)Error: Could not find Go version '$version_to_find' for platform '$platform'.${RESET}"
    exit 1
  fi

  # Return the first match if multiple exist (e.g., for "1.21")
  echo "$version_info" | head -n 1
}

function remove_go() {
  local installed_version
  installed_version=$(what_installed_version)
  if [[ -z "$installed_version" ]]; then
    echo "$($TEXT_COLOR $YELLOW)Go is not installed. Nothing to remove.${RESET}"
    return 0
  fi

  local goroot
  goroot=$(go env GOROOT 2>/dev/null || echo "$HOME/.go")

  echo "$($TEXT_COLOR $RED)Removing Go version $installed_version${RESET} from $goroot"

  if [[ -d "$goroot" ]]; then
    if ! rm -rf "$goroot"; then
      echo "$($TEXT_COLOR $RED)Error: Failed to remove $goroot.${RESET}" >&2
      echo "You may need to run with sudo: $($TEXT_COLOR $YELLOW)sudo bash go.sh remove${RESET}" >&2
      exit 1
    fi
  fi

  local shell_profile
  shell_profile=$(what_shell_profile)
  if [[ -f "$shell_profile" ]]; then
    echo "Creating a backup of your shell profile to ${shell_profile}.bak"
    cp -a "$shell_profile" "${shell_profile}.bak"
    echo "Removing Go environment variables from ${shell_profile}"
    sed -i.bak -e '/# GoLang ENV/,/End GoLang ENV/d' "$shell_profile"
  fi

  echo "$($TEXT_COLOR $GREEN)Go uninstalled successfully!${RESET}"
  echo "Please restart your shell or run: $($TEXT_COLOR $YELLOW)source ${shell_profile}${RESET}"
}

function install_go() {
  local version_to_install="$1"
  local platform="$2"
  local goroot="$HOME/.go"
  local gopath="$HOME/go"

  # --- Check if the requested version is already installed ---
  local current_version
  current_version=$(what_installed_version)
  local target_version_str="$version_to_install"

  if [[ "$target_version_str" == "latest" ]]; then
    # find_version_info returns: filename sha256 version_str
    target_version_str=$(find_version_info "latest" "$platform" | awk '{print $3}' | sed 's/go//')
  fi

  if [[ "$current_version" == "$target_version_str" ]]; then
    echo "$($TEXT_COLOR $GREEN)Go version $current_version is already installed. Nothing to do.${RESET}"
    return 0
  fi
  # --- End of check ---

  # --- Restore from backup if available ---
  if [[ "$version_to_install" != "latest" ]]; then
    # Find exact version from partial version string if needed
    local target_version="$version_to_install"
    if [[ ! -d "${goroot}-${target_version}" ]]; then
        local matching_dirs
        matching_dirs=$(find "$HOME" -maxdepth 1 -type d -name ".go-${version_to_install}*" | sort -V -r)
        if [[ -n "$matching_dirs" ]]; then
            local latest_match
            latest_match=$(echo "$matching_dirs" | head -n 1)
            target_version=${latest_match##*-}
        fi
    fi

    local target_backup_dir="${goroot}-${target_version}"
    if [[ -d "$target_backup_dir" ]]; then
      echo "$($TEXT_COLOR $GREEN)Found existing backup for Go version $target_version.${RESET}"
      echo "Restoring from $target_backup_dir..."

      if [[ -d "$goroot" ]]; then
        local current_version
        current_version=$(what_installed_version)
        if [[ -n "$current_version" && "$current_version" != "$target_version" ]]; then
          local current_backup_dir="${goroot}-${current_version}"
          echo "Moving current installation to $current_backup_dir..."
          rm -rf "$current_backup_dir"
          mv "$goroot" "$current_backup_dir"
        fi
      fi

      mv "$target_backup_dir" "$goroot"

      local shell_profile
      shell_profile=$(what_shell_profile)
      if ! grep -q "export GOROOT=$goroot" "$shell_profile"; then
          update_shell_profile "$goroot" "$gopath" "$shell_profile"
      fi

      echo "$($TEXT_COLOR $GREEN)Go version $target_version restored successfully!${RESET}"
      echo "Please restart your shell or run: $($TEXT_COLOR $YELLOW)source \"$shell_profile\"${RESET}"
      return 0
    fi
  fi
  # --- End of restore logic ---

  local version_info
  read -r filename sha256 version_str < <(find_version_info "$version_to_install" "$platform")
  local version_number
  version_number=${version_str#go}

  echo "Downloading $($TEXT_COLOR $CYAN)Go $version_number${RESET} ($filename) to temporary directory..."
  local download_url="https://dl.google.com/go/$filename"
  local download_cmd
  download_cmd=$(get_download_command)
  local temp_file_path="$TMP_DIR/$filename"

  if [[ "$download_cmd" == *"curl"* ]]; then
    curl --fail --location --progress-bar "$download_url" -o "$temp_file_path"
  else
    wget --quiet --show-progress --continue "$download_url" -O "$temp_file_path"
  fi

  echo "Verifying checksum..."
  local calculated_sha
  if command -v sha256sum &>/dev/null; then
    calculated_sha=$(sha256sum "$temp_file_path" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then # macOS
    calculated_sha=$(shasum -a 256 "$temp_file_path" | awk '{print $1}')
  else
    echo "$($TEXT_COLOR $YELLOW)Warning: Could not find sha256sum or shasum to verify download.${RESET}"
    calculated_sha="$sha256" # Skip check
  fi

  if [[ "$calculated_sha" != "$sha256" ]]; then
    echo "$($TEXT_COLOR $RED)Error: Checksum mismatch! File is corrupt or has been tampered with.${RESET}" >&2
    # The trap will clean up the temp file
    exit 1
  fi
  echo "Checksum verified."

  if [[ -d "$goroot" ]]; then
    local current_version=""
    if [[ -x "$goroot/bin/go" ]]; then
      current_version=$("$goroot/bin/go" version 2>/dev/null | sed -n 's/.*go\([0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?\).*/\1/p' || echo "")
    fi

    if [[ -n "$current_version" ]]; then
      local backup_dir="${goroot}-${current_version}"
      echo "Moving existing Go installation to $backup_dir..."
      rm -rf "$backup_dir"
      mv "$goroot" "$backup_dir"
    else
      echo "Moving existing Go installation to $goroot.bak..."
      rm -rf "$goroot.bak"
      mv "$goroot" "$goroot.bak"
    fi
  fi

  echo "Extracting $filename to $goroot..."
  mkdir -p "$goroot"
  tar -xzf "$temp_file_path" -C "$goroot" --strip-components=1
  # The trap will clean up the temp file

  mkdir -p "$gopath"/{src,pkg,bin}

  local shell_profile
  shell_profile=$(what_shell_profile)
  update_shell_profile "$goroot" "$gopath" "$shell_profile"

  echo "$($TEXT_COLOR $GREEN)Go $version_number installed successfully!${RESET}"
  echo "Please restart your shell or run: $($TEXT_COLOR $YELLOW)source \"$shell_profile\"${RESET}"
}

function update_shell_profile() {
    local goroot="$1"
    local gopath="$2"
    local shell_profile="$3"

    touch "$shell_profile"

    # Remove old entries before adding new ones
    if grep -q "# GoLang ENV" "$shell_profile"; then
        sed -i.bak -e '/# GoLang ENV/,/End GoLang ENV/d' "$shell_profile"
    fi

    echo "Updating shell profile: $shell_profile"
    {
        echo ''
        echo '# GoLang ENV'
        echo "export GOROOT=$goroot"
        echo "export GOPATH=$gopath"
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin'
        echo '# End GoLang ENV'
    } >>"$shell_profile"
}

# --- Main Execution ---

function print_welcome() {
  echo -e "$($TEXT_COLOR $CYAN)
\t ██████╗  ██████╗     ███████╗███████╗████████╗██╗   ██╗██████╗
\t██╔════╝ ██╔═══██╗    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
\t██║  ███╗██║   ██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
\t██║   ██║██║   ██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
\t╚██████╔╝╚██████╔╝    ███████║███████╗   ██║   ╚██████╔╝██║
${RESET}"
}

function print_help() {
  echo -e "\t$($TEXT_COLOR $BLUE)go.sh${RESET} - A tool to easily install, update, or uninstall Go."
  echo ""
  echo -e "\t$($TEXT_COLOR $GREEN)USAGE:${RESET}"
  echo -e "\t  bash go.sh [command]"
  echo ""
  echo -e "\t$($TEXT_COLOR $GREEN)COMMANDS:${RESET}"
  echo -e "\t  $($TEXT_COLOR $YELLOW)install [version]${RESET}\tInstalls a specific Go version (e.g., '1.21.5' or '1.21'). Defaults to latest."
  echo -e "\t  $($TEXT_COLOR $YELLOW)update${RESET}\t\t\tUpdates to the latest stable version of Go."
  echo -e "\t  $($TEXT_COLOR $YELLOW)remove${RESET}\t\t\tUninstalls Go from your system."
  echo -e "\t  $($TEXT_COLOR $YELLOW)check [version]${RESET}\t\tChecks if a specific version is installed. Defaults to latest."
  echo -e "\t  $($TEXT_COLOR $YELLOW)help${RESET}\t\t\tPrints this help message."
  echo ""
  echo -e "\t$($TEXT_COLOR $GREEN)EXAMPLES:${RESET}"
  echo -e "\t  bash go.sh install"
  echo -e "\t  bash go.sh install 1.21.5"
  echo -e "\t  bash go.sh update"
}

function main() {
  print_welcome

  local cmd="${1:-install}"
  local version_arg="${2:-latest}"
  local platform
  platform=$(what_platform)

  case "$cmd" in
  install)
    local current_version
    current_version=$(what_installed_version)

    if [[ "$version_arg" == "latest" ]]; then
      if [[ -n "$current_version" ]]; then
        read -r _ _ latest_version_str < <(find_version_info "latest" "$platform")
        local latest_version=${latest_version_str#go}
        if [[ "$current_version" == "$latest_version" ]]; then
          echo "You already have the latest Go version ($current_version) installed."
          exit 0
        fi
      fi
    elif [[ -n "$current_version" && "$current_version" == *"$version_arg"* ]]; then
      echo "Go version $version_arg is already installed."
      exit 0
    fi
    install_go "$version_arg" "$platform"
    ;;
  update)
    local current_version
    current_version=$(what_installed_version)
    read -r _ _ latest_version_str < <(find_version_info "latest" "$platform")
    local latest_version=${latest_version_str#go}

    if [[ "$current_version" == "$latest_version" ]]; then
      echo "$($TEXT_COLOR $GREEN)You are already running the latest version of Go ($current_version).${RESET}"
      exit 0
    fi
    echo "Updating Go from version $current_version to $latest_version..."
    install_go "latest" "$platform"
    ;;
  remove)
    remove_go
    ;;
  check)
    # First, validate that the version exists remotely.
    # find_version_info will exit with an error if not found.
    local version_info
    read -r _ _ remote_version_str < <(find_version_info "$version_arg" "$platform")
    local remote_version=${remote_version_str#go}

    local current_version
    current_version=$(what_installed_version)

    if [[ -z "$current_version" ]]; then
      echo "Go is not installed, but version $remote_version is a valid version."
      exit 1
    fi

    echo "Installed version: $current_version"
    echo "Checked version:   $remote_version"

    if [[ "$current_version" == "$remote_version" ]]; then
        echo "$($TEXT_COLOR $GREEN)Go version $remote_version is installed.${RESET}"
        exit 0
    else
        echo "Go version $remote_version is NOT installed. Current version is $current_version."
        exit 1
    fi
    ;;
  help | --help | -h)
    print_help
    ;;
  *)
    echo "$($TEXT_COLOR $RED)Error: Unknown command '$cmd'.${RESET}" >&2
    print_help
    exit 1
    ;;
  esac
}

main "${_main_args[@]}" || {
  echo "$($TEXT_COLOR $RED)An unexpected error occurred.${RESET}" >&2
  exit 1
}
