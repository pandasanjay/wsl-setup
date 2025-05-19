#!/bin/bash

# WSL Storage Cleanup Script (v3)
#
# This script helps identify and clean up unnecessary files in your WSL environment
# to free up disk space. It will always ask for confirmation before deleting anything.
#
# IMPORTANT:
# - Review each section carefully before confirming deletion.
# - While this script targets common temporary/cache locations, ensure you
#   don't have critical data in these areas if you've manually placed it there.
# - Some commands require sudo privileges and will prompt for your password.
# - For WSL2, cleaning files inside WSL doesn't automatically shrink the virtual
#   disk (.vhdx) file on Windows. You may need to compact it manually from
#   PowerShell after running this script. (e.g., Optimize-VHD -Path <pathToVhdx> -Mode Full)

# Exit immediately if a command exits with a non-zero status.
# set -e # Temporarily commenting out during development of error handling
# Treat unset variables as an error when substituting.
set -u
# Causes a pipeline to return the exit status of the last command in the pipe
# that returned a non-zero return value.
set -o pipefail

# --- Configuration ---
# Threshold for considering a directory "large" in the home directory scan (e.g., 1G, 500M)
LARGE_DIR_THRESHOLD="500M"
# Number of largest directories to show in home directory scan
TOP_N_DIRS=10

# --- Helper Functions (primarily for user-space paths) ---

# Function to ask a yes/no question
ask_yes_no() {
    local prompt="$1"
    while true; do
        read -r -p "$prompt [y/N]: " response
        case "$response" in
            [Yy]* ) return 0;; # Yes
            [Nn]* | "" ) return 1;; # No or Enter
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Function to get directory size in human-readable format (for user paths)
get_dir_size() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "0B" # Suppress du errors for non-readable subdirs
    else
        echo "0B"
    fi
}

# Function to get file count in a directory (for user paths)
get_file_count() {
    local path="$1"
    if [ -d "$path" ]; then
        find "$path" -type f 2>/dev/null | wc -l || echo "0" # Suppress find errors
    else
        echo "0"
    fi
}

# --- Variables ---
TOTAL_FREED_SPACE_BYTES=0
DISTRO_TYPE=""

# --- Script Start ---
echo "========================================="
echo "  WSL Storage Cleanup Assistant"
echo "========================================="
echo "This script will guide you through cleaning up your WSL environment."
echo "It will show potential space savings and ask for confirmation before any deletion."
echo -e "\nIMPORTANT: For WSL2, after cleaning files within WSL, the virtual disk (.vhdx)"
echo "file on your Windows system does NOT shrink automatically. You may need to"
echo "compact it. Search for 'WSL2 compact virtual disk' for instructions."
echo "Typically, this involves shutting down WSL (wsl --shutdown) and then using"
echo "Optimize-VHD in PowerShell (e.g., Optimize-VHD -Path <pathToYourExt4.vhdx> -Mode Full)."
echo -e "You can find the path to your .vhdx file using 'wsl -l -v' in PowerShell or CMD.\n"

if ! ask_yes_no "Do you want to proceed with the cleanup analysis?"; then
    echo "Exiting script."
    exit 0
fi

# --- Detect Distro Type (for package manager) ---
if command -v apt-get &> /dev/null; then
    DISTRO_TYPE="debian_ubuntu"
elif command -v dnf &> /dev/null; then
    DISTRO_TYPE="fedora_rhel"
elif command -v yum &> /dev/null; then # Older Fedora/RHEL/CentOS
    DISTRO_TYPE="fedora_rhel_old"
elif command -v pacman &> /dev/null; then
    DISTRO_TYPE="arch"
elif command -v zypper &> /dev/null; then
    DISTRO_TYPE="suse"
else
    echo "Could not automatically determine your distribution's package manager."
    echo "Package manager specific cleanup will be skipped."
fi

# --- 1. Package Manager Cache Cleanup ---
echo -e "\n--- 1. Package Manager Cache Cleanup ---"
freed_this_section_bytes=0
case "$DISTRO_TYPE" in
    "debian_ubuntu")
        echo "Detected Debian/Ubuntu based system (apt)."
        echo "APT cache (`/var/cache/apt/archives` and others) can store downloaded package files."
        echo "Running 'sudo apt-get clean' removes downloaded .deb files."
        echo "Running 'sudo apt-get autoclean' removes old downloaded .deb files."
        echo "Running 'sudo apt-get autoremove' removes packages that were automatically installed to satisfy dependencies for other packages and are now no longer needed."

        apt_cache_dir="/var/cache/apt/archives"
        current_apt_cache_display_size=$(sudo du -sh "$apt_cache_dir" 2>/dev/null | awk '{print $1}' || echo '0B')
        echo "Current estimated size of $apt_cache_dir: $current_apt_cache_display_size"
        apt_cache_size_before=$(sudo du -sb "$apt_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0)


        if ask_yes_no "Clean APT package cache? (sudo apt-get clean && sudo apt-get autoclean)"; then
            echo "Cleaning APT cache..."
            sudo apt-get clean
            sudo apt-get autoclean
            apt_cache_size_after=$(sudo du -sb "$apt_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0)
            freed_apt_cache=$((apt_cache_size_before - apt_cache_size_after))
            if [ "$freed_apt_cache" -lt 0 ]; then freed_apt_cache=0; fi
            TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_apt_cache))
            freed_this_section_bytes=$((freed_this_section_bytes + freed_apt_cache))
            echo "APT cache cleaned. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_apt_cache)"
        else
            echo "Skipping APT cache cleanup."
        fi

        echo -e "\nChecking for orphaned packages (dependencies no longer needed)..."
        if ask_yes_no "Remove orphaned packages? (sudo apt-get autoremove)"; then
            echo "Removing orphaned packages..."
            autoremove_output=$(sudo apt-get -y autoremove 2>&1)
            echo "$autoremove_output"
            freed_autoremove_str=$(echo "$autoremove_output" | grep -oP '(?<=After this operation, )[0-9.]+[ ][kKMGT]?B(?= of disk space will be freed.)' || echo "0B")
            if [[ "$freed_autoremove_str" != "0B" ]]; then
                freed_autoremove_val_bytes=$(numfmt --from=iec "$freed_autoremove_str" 2>/dev/null || echo 0)
                TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_autoremove_val_bytes))
                freed_this_section_bytes=$((freed_this_section_bytes + freed_autoremove_val_bytes))
                echo "Orphaned packages removed. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_autoremove_val_bytes)"
            else
                echo "Orphaned packages removed (or none to remove). Unable to parse exact space freed from output, but operation completed."
            fi
        else
            echo "Skipping orphaned package removal."
        fi
        ;;
    "fedora_rhel" | "fedora_rhel_old")
        pkg_cmd="dnf"
        if [ "$DISTRO_TYPE" == "fedora_rhel_old" ]; then pkg_cmd="yum"; fi
        echo "Detected Fedora/RHEL based system ($pkg_cmd)."
        cache_dir_path="/var/cache/$pkg_cmd"
        current_pkg_cache_display_size=$(sudo du -sh "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo '0B')
        echo "Current estimated $pkg_cmd cache size ($cache_dir_path): $current_pkg_cache_display_size"
        
        if ask_yes_no "Clean $pkg_cmd package cache? (sudo $pkg_cmd clean all)"; then
            echo "Cleaning $pkg_cmd cache..."
            size_before_bytes=$(sudo du -sb "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo 0)
            sudo $pkg_cmd clean all
            size_after_bytes=$(sudo du -sb "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo 0)
            freed_pkg_cache=$((size_before_bytes - size_after_bytes))
            if [ "$freed_pkg_cache" -lt 0 ]; then freed_pkg_cache=0; fi

            TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_pkg_cache))
            freed_this_section_bytes=$((freed_this_section_bytes + freed_pkg_cache))
            echo "$pkg_cmd cache cleaned. Approximate space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_pkg_cache)"
        else
            echo "Skipping $pkg_cmd cache cleanup."
        fi
        ;;
    "arch")
        echo "Detected Arch Linux based system (pacman)."
        pacman_cache_dir="/var/cache/pacman/pkg/"
        pacman_cache_size_display=$(sudo du -sh "$pacman_cache_dir" 2>/dev/null | awk '{print $1}' || echo '0B')
        echo "Current Pacman cache size ($pacman_cache_dir): $pacman_cache_size_display"
        if ask_yes_no "Clean Pacman cache (remove all uninstalled and all cached versions of installed packages)? (sudo pacman -Scc)"; then
            echo "Executing 'sudo pacman -Scc'. Please respond to its prompts."
            size_before_bytes=$(sudo du -sb "$pacman_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0)
            sudo pacman -Scc # This command is interactive
            size_after_bytes=$(sudo du -sb "$pacman_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0)
            freed_pacman_cache=$((size_before_bytes - size_after_bytes))
            if [ "$freed_pacman_cache" -lt 0 ]; then freed_pacman_cache=0; fi

            TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_pacman_cache))
            freed_this_section_bytes=$((freed_this_section_bytes + freed_pacman_cache))
            echo "Pacman cache cleaned. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_pacman_cache)"
        else
            echo "Skipping Pacman cache cleanup. You can also use 'paccache -r' to remove old versions more selectively."
        fi
        ;;
    "suse")
        echo "Detected SUSE/openSUSE based system (zypper)."
        cache_dir_path="/var/cache/zypp"
        current_zypper_cache_display_size=$(sudo du -sh "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo '0B')
        echo "Current Zypper cache size ($cache_dir_path): $current_zypper_cache_display_size"

        if ask_yes_no "Clean Zypper package cache? (sudo zypper clean -a)"; then
            echo "Cleaning Zypper cache..."
            size_before_bytes=$(sudo du -sb "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo 0)
            sudo zypper clean -a # -a for all types of caches
            size_after_bytes=$(sudo du -sb "$cache_dir_path" 2>/dev/null | awk '{print $1}' || echo 0)
            freed_zypper_cache=$((size_before_bytes - size_after_bytes))
            if [ "$freed_zypper_cache" -lt 0 ]; then freed_zypper_cache=0; fi

            TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_zypper_cache))
            freed_this_section_bytes=$((freed_this_section_bytes + freed_zypper_cache))
            echo "Zypper cache cleaned. Approximate space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_zypper_cache)"
        else
            echo "Skipping Zypper cache cleanup."
        fi
        ;;
    *)
        echo "Package manager cleanup skipped (unsupported or undetermined distro)."
        ;;
esac
echo "Space freed in this section: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_this_section_bytes)"

# --- 2. System Temporary Files ---
echo -e "\n--- 2. System Temporary Files ---"
freed_this_section_bytes=0
# /tmp
tmp_dir="/tmp"
tmp_size_display=$(sudo du -sh "$tmp_dir" 2>/dev/null | awk '{print $1}' || echo '0B')
tmp_files_count=$(sudo find "$tmp_dir" -mindepth 1 -type f 2>/dev/null | wc -l || echo '0') # Count files not dirs
echo "System temporary directory ($tmp_dir): $tmp_size_display, $tmp_files_count files."
echo "Files in $tmp_dir are usually safe to delete, but active processes might use some."
echo "A reboot typically clears this. Alternatively, you can delete files older than a certain age."
# Check if there's anything to delete (files or directories)
if [ "$(sudo find "$tmp_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    if ask_yes_no "Delete all contents of $tmp_dir? (Requires sudo. Use with caution)"; then
        echo "Deleting contents of $tmp_dir..."
        size_before_bytes=$(sudo du -sb "$tmp_dir" 2>/dev/null | awk '{print $1}' || echo 0)
        sudo find "$tmp_dir" -mindepth 1 -delete
        size_after_bytes=$(sudo du -sb "$tmp_dir" 2>/dev/null | awk '{print $1}' || echo 0)
        freed_tmp=$((size_before_bytes - size_after_bytes))
        if [ "$freed_tmp" -lt 0 ]; then freed_tmp=0; fi
        TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_tmp))
        freed_this_section_bytes=$((freed_this_section_bytes + freed_tmp))
        echo "Contents of $tmp_dir deleted. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_tmp)"
    else
        echo "Skipping $tmp_dir cleanup."
    fi
else
    echo "$tmp_dir appears empty."
fi

# /var/tmp
var_tmp_dir="/var/tmp"
var_tmp_size_display=$(sudo du -sh "$var_tmp_dir" 2>/dev/null | awk '{print $1}' || echo '0B')
var_tmp_files_count=$(sudo find "$var_tmp_dir" -mindepth 1 -type f 2>/dev/null | wc -l || echo '0') # Count files not dirs
echo "System temporary directory ($var_tmp_dir): $var_tmp_size_display, $var_tmp_files_count files."
echo "Files in $var_tmp_dir persist across reboots but are still for temporary data."
if [ "$(sudo find "$var_tmp_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    if ask_yes_no "Delete all contents of $var_tmp_dir? (Requires sudo. Use with caution)"; then
        echo "Deleting contents of $var_tmp_dir..."
        size_before_bytes=$(sudo du -sb "$var_tmp_dir" 2>/dev/null | awk '{print $1}' || echo 0)
        sudo find "$var_tmp_dir" -mindepth 1 -delete
        size_after_bytes=$(sudo du -sb "$var_tmp_dir" 2>/dev/null | awk '{print $1}' || echo 0)
        freed_var_tmp=$((size_before_bytes - size_after_bytes))
        if [ "$freed_var_tmp" -lt 0 ]; then freed_var_tmp=0; fi
        TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_var_tmp))
        freed_this_section_bytes=$((freed_this_section_bytes + freed_var_tmp))
        echo "Contents of $var_tmp_dir deleted. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_var_tmp)"
    else
        echo "Skipping $var_tmp_dir cleanup."
    fi
else
    echo "$var_tmp_dir appears empty."
fi
echo "Space freed in this section: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_this_section_bytes)"


# --- 3. User Cache Files ---
echo -e "\n--- 3. User Cache Files ---"
freed_this_section_bytes=0
user_cache_dir="$HOME/.cache"
if [ -d "$user_cache_dir" ]; then
    user_cache_size_display=$(get_dir_size "$user_cache_dir") # Uses helper, runs as user
    user_cache_content_count=$(find "$user_cache_dir" -mindepth 1 -print 2>/dev/null | wc -l || echo "0") # Count any content

    echo "User cache directory ($user_cache_dir): $user_cache_size_display, $user_cache_content_count items (files/dirs)."
    echo "Applications store cache data here. It's generally safe to delete, but apps will regenerate it."

    if [ "$user_cache_content_count" -gt 0 ]; then
        if ask_yes_no "Delete contents of your user cache directory ($user_cache_dir)?"; then
            echo "Attempting to delete contents of $user_cache_dir as current user..."
            size_before_bytes=$(du -sb "$user_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0) # Runs as user

            # Try deleting as user first, capture stderr
            # We need to temporarily disable `set -e` or `set -o pipefail` for this to not exit the script on error
            set +e # Disable exit on error
            set +o pipefail
            deletion_errors=$(find "$user_cache_dir" -mindepth 1 -delete 2>&1)
            deletion_exit_code=$?
            set -e # Re-enable exit on error
            set -o pipefail

            if [ $deletion_exit_code -ne 0 ]; then
                echo "---------------------------------------------------------------------"
                echo "WARNING: Could not delete all items in $user_cache_dir as current user."
                echo "Error messages from attempt:"
                echo "$deletion_errors"
                echo "---------------------------------------------------------------------"
                if ask_yes_no "Attempt to delete ALL contents of $user_cache_dir using sudo? (Use with caution)"; then
                    echo "Attempting to delete contents of $user_cache_dir with sudo..."
                    # size_before_bytes is already set from the user attempt, which is fine.
                    # Or, we can re-fetch with sudo if we want the most accurate "before sudo" state.
                    # For simplicity, we use the existing size_before_bytes.
                    sudo find "$user_cache_dir" -mindepth 1 -delete
                    echo "Sudo deletion attempt finished."
                else
                    echo "Skipping sudo deletion for $user_cache_dir."
                fi
            else
                echo "User cache contents deleted successfully (as user)."
            fi

            # Recalculate freed space after all attempts
            size_after_bytes=$(du -sb "$user_cache_dir" 2>/dev/null | awk '{print $1}' || echo 0) # Runs as user
            freed_user_cache=$((size_before_bytes - size_after_bytes))
            if [ "$freed_user_cache" -lt 0 ]; then freed_user_cache=0; fi

            TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_user_cache))
            freed_this_section_bytes=$((freed_this_section_bytes + freed_user_cache))
            echo "User cache cleanup attempt finished. Space freed in this step: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_user_cache)"
        else
            echo "Skipping user cache cleanup."
        fi
    else
        echo "$user_cache_dir is empty or has no top-level contents."
    fi
else
    echo "User cache directory ($user_cache_dir) not found."
fi
echo "Space freed in this section: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_this_section_bytes)"

# --- 4. Old Log Files ---
echo -e "\n--- 4. Old Log Files ---"
freed_this_section_bytes=0
log_dir="/var/log"
echo "System log directory ($log_dir)."
echo "Old, rotated log files (e.g., .gz, .1, .old) can be removed."
old_logs_size_bytes=$(sudo find "$log_dir" \( -name "*.gz" -o -name "*.xz" -o -name "*.bz2" -o -name "*.[0-9]" -o -name "*.old" \) -type f -print0 2>/dev/null | xargs -0 -r sudo du -cb 2>/dev/null | grep total | awk '{print $1}' || echo 0)
old_logs_size_human=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$old_logs_size_bytes")

if [ "$old_logs_size_bytes" -gt 0 ]; then
    echo "Found old/rotated log files totaling: $old_logs_size_human"
    if ask_yes_no "Delete these old/rotated log files? (Requires sudo)"; then
        echo "Deleting old log files..."
        sudo find "$log_dir" \( -name "*.gz" -o -name "*.xz" -o -name "*.bz2" -o -name "*.[0-9]" -o -name "*.old" \) -type f -print -delete
        TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + old_logs_size_bytes))
        freed_this_section_bytes=$((freed_this_section_bytes + old_logs_size_bytes))
        echo "Old log files deleted. Space freed: $old_logs_size_human"
    else
        echo "Skipping old log file cleanup."
    fi
else
    echo "No significant old/rotated log files found with common patterns."
fi
echo "Space freed in this section: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_this_section_bytes)"


# --- 5. Journald Logs (if systemd is used) ---
if command -v journalctl &> /dev/null; then
    echo -e "\n--- 5. Systemd Journald Log Cleanup ---"
    freed_this_section_bytes=0 
    current_journal_size_text=$(sudo journalctl --disk-usage) 
    echo "Current Systemd journal disk usage: $current_journal_size_text"
    echo "You can vacuum journal logs by size or time."

    if ask_yes_no "Vacuum journal logs? (e.g., to keep last 100MB or last 2 weeks)"; then
        read -r -p "Vacuum by size (e.g., 100M, 1G) or time (e.g., 2weeks, 1months)? Enter value or leave blank to skip: " vacuum_value
        if [ -n "$vacuum_value" ]; then
            size_before_bytes=$(echo "$current_journal_size_text" | awk '/Archived and active journals take up/{print $6$7}' | sed 's/(//' | numfmt --from=iec 2>/dev/null || \
                                echo "$current_journal_size_text" | awk '/take up.*on disk/{print $5}' | numfmt --from=iec 2>/dev/null || echo 0) # More robust parsing
            
            echo "Attempting to vacuum journal..."
            vacuum_success=false
            if [[ "$vacuum_value" =~ M|G|K|MB|GB|KB$ ]]; then 
                echo "Using vacuum-size=$vacuum_value"
                sudo journalctl --vacuum-size="$vacuum_value" && vacuum_success=true
            elif [[ "$vacuum_value" =~ days|weeks|months|years$ ]]; then 
                echo "Using vacuum-time=$vacuum_value"
                sudo journalctl --vacuum-time="$vacuum_value" && vacuum_success=true
            else
                echo "Invalid format for vacuum value. Expected size (e.g., 100M) or time (e.g., 2weeks)."
                echo "Skipping journal vacuuming for this attempt."
            fi

            if [ "$vacuum_success" = true ]; then
                new_journal_size_text=$(sudo journalctl --disk-usage)
                size_after_bytes=$(echo "$new_journal_size_text" | awk '/Archived and active journals take up/{print $6$7}' | sed 's/(//' | numfmt --from=iec 2>/dev/null || \
                                 echo "$new_journal_size_text" | awk '/take up.*on disk/{print $5}' | numfmt --from=iec 2>/dev/null || echo 0)
                freed_journal=$((size_before_bytes - size_after_bytes))
                if [ "$freed_journal" -lt 0 ]; then freed_journal=0; fi 
                TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_journal))
                freed_this_section_bytes=$((freed_this_section_bytes + freed_journal))
                echo "Journal vacuumed. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_journal). New size: $new_journal_size_text"
            else
                 echo "Journal vacuuming command may have failed or was skipped due to invalid input."
            fi
        else
            echo "Skipping journal vacuuming as no value was entered."
        fi
    else
        echo "Skipping journal log cleanup."
    fi
else
    echo -e "\nSystemd journalctl not found, skipping journal log cleanup."
    freed_this_section_bytes=0 
fi
echo "Space freed in this section: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_this_section_bytes)"


# --- 6. Docker Cleanup (if Docker is installed) ---
if command -v docker &> /dev/null; then
    echo -e "\n--- 6. Docker Cleanup ---"
    echo "Docker can consume significant space with unused images, containers, volumes, and build cache."
    echo "Running 'docker system df' to show current Docker disk usage:"
    sudo docker system df 

    if ask_yes_no "Prune unused Docker resources (stopped containers, dangling images, unused networks, build cache)? (sudo docker system prune)"; then
        echo "Pruning unused Docker resources..."
        sudo docker system prune -f 
        echo "Docker system prune completed. Check Docker's output above for reclaimed space."
    else
        echo "Skipping basic Docker prune."
    fi

    if ask_yes_no "Aggressively prune ALL unused Docker images (not just dangling ones)? (sudo docker image prune -a)"; then
        echo "Pruning all unused Docker images..."
        sudo docker image prune -a -f
        echo "All unused Docker images pruned. Check Docker's output above for reclaimed space."
    else
        echo "Skipping aggressive Docker image prune."
    fi
    echo "Space freed in this section: (See Docker's output for details. This script does not add Docker's freed space to the total.)"
else
    echo -e "\nDocker command not found, skipping Docker cleanup."
fi


# --- 7. Identify Large Directories in Home ---
echo -e "\n--- 7. Identify Large Directories & Files in Home Directory ---"
echo "This section will help you find large directories and files within your home directory ($HOME)."
echo "It will NOT delete anything automatically. You should review these and decide manually."

if ask_yes_no "Scan for large directories (>$LARGE_DIR_THRESHOLD) in your home directory?"; then
    echo "Searching for directories larger than $LARGE_DIR_THRESHOLD in $HOME (this might take a while)..."
    # Using `find` with `-size` is not standard for directories based on content size.
    # `du` is needed, then `awk` to filter.
    # Exclude common cache/metadata/build directories. Runs as user.
    # The previous find ... | xargs du ... | awk was better for this.
    # Let's refine the find part to list directories, then du them, then filter.
    find "$HOME" -mindepth 1 -type d \( \
        -path "$HOME/.cache" -o \
        -path "$HOME/.local/share/Trash" -o \
        -path "$HOME/*/.git" -o \
        -path "$HOME/*/.idea" -o \
        -path "$HOME/*/.vscode" -o \
        -path "$HOME/*/.npm" -o \
        -path "$HOME/*/.cargo" -o \
        -path "$HOME/*/.rustup" -o \
        -path "$HOME/*/.gradle" -o \
        -path "$HOME/*/.m2" -o \
        -path "$HOME/.local/lib/python*" -o \
        -path "$HOME/snap" -o \
        -path "*/node_modules" -o \
        -path "*/target" -o \
        -path "*/build" \
        \) -prune -o \
        -type d -print0 2>/dev/null | xargs -0 -I {} du -sh --apparent-size "{}" 2>/dev/null | \
        awk -v th_gb=$(numfmt --from=iec $LARGE_DIR_THRESHOLD) '
            {
                size_bytes=0;
                unit = substr($1, length($1), 1);
                val = substr($1, 1, length($1)-1);
                if (unit == "K") size_bytes = val * 1024;
                else if (unit == "M") size_bytes = val * 1024*1024;
                else if (unit == "G") size_bytes = val * 1024*1024*1024;
                else if (unit == "T") size_bytes = val * 1024*1024*1024*1024;
                else if (unit ~ /[0-9]/) size_bytes = $1; # Bytes, no suffix

                if (size_bytes >= th_gb) print $0;
            }
        ' | sort -rh | head -n "$TOP_N_DIRS"


    echo "---"
    echo "Common large directories to investigate (if not listed above or for deeper scan):"
    echo "  - ~/Downloads"
    echo "  - Project directories with 'node_modules', 'target/', 'build/', 'venv/', '.venv/'"
    echo "  - ~/snap (if you use snaps and they store large data in home)"
    echo "  - ~/.local/share/Trash (user trash)"

    trash_dir_user="$HOME/.local/share/Trash/files"
    if [ -d "$trash_dir_user" ]; then
        trash_size_user=$(get_dir_size "$trash_dir_user") 
        trash_files_user=$(find "$trash_dir_user" -mindepth 1 -print 2>/dev/null | wc -l || echo "0")
        if [ "$trash_files_user" -gt 0 ]; then
            echo "User trash ($trash_dir_user): $trash_size_user, $trash_files_user items."
            if ask_yes_no "Empty your user trash ($trash_dir_user)?"; then
                size_before_bytes=$(du -sb "$trash_dir_user" 2>/dev/null | awk '{print $1}' || echo 0) 
                rm -rf "$trash_dir_user"/*
                size_after_bytes=$(du -sb "$trash_dir_user" 2>/dev/null | awk '{print $1}' || echo 0) 
                freed_trash=$((size_before_bytes - size_after_bytes))
                if [ "$freed_trash" -lt 0 ]; then freed_trash=0; fi
                TOTAL_FREED_SPACE_BYTES=$((TOTAL_FREED_SPACE_BYTES + freed_trash))
                echo "User trash emptied. Space freed: $(numfmt --to=iec-i --suffix=B --format="%.2f" $freed_trash)"
            fi
        else
            echo "User trash ($trash_dir_user) is empty."
        fi
    fi
else
    echo "Skipping scan for large directories in home."
fi

echo -e "\nSearching for common large file types (e.g. .log, .tmp, .bak, .old, .iso, .zip) in $HOME..."
echo "This is for identification only. No files will be deleted automatically."
find "$HOME" -path "$HOME/.cache" -prune -o -path "$HOME/.local/share/Trash" -prune -o \
    \( -iname "*.log" -o -iname "*.tmp" -o -iname "*.bak" -o -iname "*.old" -o -iname "*.swp" -o -iname "*.iso" -o -iname "*.zip" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.deb" -o -iname "*.rpm" -o -iname "*.AppImage" \) \
    -type f -size +100M -print0 2>/dev/null | xargs -0 -r du -h --apparent-size 2>/dev/null | sort -rh | head -n "$TOP_N_DIRS"
echo "Review the list above. If you recognize any unnecessary large files, you can delete them manually."


# --- Summary ---
echo -e "\n--- Summary ---"
total_freed_human=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$TOTAL_FREED_SPACE_BYTES")
echo "Total space freed by this script (approximate, excluding Docker if not parsed): $total_freed_human"

echo -e "\nFurther recommendations:"
echo " - Manually review the large directories/files identified in your home directory."
echo " - If you use WSL2: Remember to potentially compact your WSL2 virtual disk (.vhdx file) from Windows PowerShell."
echo "   1. Shut down WSL: 'wsl --shutdown' in PowerShell or CMD."
echo "   2. Find your .vhdx path: 'wsl -l -v' in PowerShell or CMD (e.g., C:\\Users\\YourUser\\AppData\\Local\\Packages\\CanonicalGroupLimited.Ubuntu_...\\LocalState\\ext4.vhdx)."
echo "   3. Run in PowerShell (as Admin): Optimize-VHD -Path \"C:\\path\\to\\your\\ext4.vhdx\" -Mode Full"
echo " - Consider tools like 'ncdu' or 'baobab' (Disk Usage Analyzer) for a more interactive exploration of disk space."
echo "   Install with: sudo apt install ncdu (or your distro's equivalent: sudo dnf install ncdu, sudo pacman -S ncdu, etc.)"
echo "   Run with: ncdu $HOME  (or ncdu / for system-wide, needs sudo)"

echo -e "\nCleanup analysis complete."
echo "========================================="

exit 0
