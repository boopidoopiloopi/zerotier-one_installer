#!/usr/bin/env bash

# ======================= GitHub repo settings =============================
GITHUB_REPO="boopidoopiloopi/zerotier-one_installer"
GITHUB_BRANCH="main"
API_BASE="https://api.github.com/repos/$GITHUB_REPO"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"
FALLBACK_MOON="0000005f38c5d870.moon"     # only used if the GitHub API is unreachable
MOONS_DIR="/var/lib/zerotier-one/moons.d"
# ==========================================================================

# Helper function to check if ZeroTier is installed
check_zt_installed() {
    if ! command -v zerotier-cli &> /dev/null; then
        echo "Error: ZeroTier is not installed on this system."
        echo "Please run the script again and select the installation option first."
        exit 1
    fi
}

# --------------------------------------------------------------------------
# GitHub helpers -- only curl is needed (parsing via grep/sed, no jq required)
# --------------------------------------------------------------------------

# List every .moon file in the repo (recursive, so subfolders also work)
fetch_moon_list() {
    curl -fsSL --max-time 20 "$API_BASE/git/trees/$GITHUB_BRANCH?recursive=1" 2>/dev/null \
        | grep -o '"path": *"[^"]*\.moon"' \
        | sed 's/"path": *"//; s/"$//'
}

# Date a moon file was ADDED = oldest commit that touches the file (ISO 8601).
# NOTE: to sort by "last updated" instead of "first added", swap head -n 1 -> tail -n 1
fetch_moon_added_date() {
    curl -fsSL --max-time 20 "$API_BASE/commits?path=$1&per_page=100" 2>/dev/null \
        | grep -o '"date": *"[^"]*"' \
        | sed 's/^"date": *"//; s/"$//' \
        | sort | head -n 1
}

# Browse the repo, let the user pick a moon (newest on top = recommended),
# then download + install it. Returns non-zero if no moon was installed.
install_moon() {
    echo "Querying GitHub ($GITHUB_REPO) for available moons..."

    # Show moons already present on this machine
    local installed
    installed=$(sudo ls -1 "$MOONS_DIR" 2>/dev/null)
    if [[ -n "$installed" ]]; then
        echo "Already installed on this machine:"
        echo "$installed" | sed 's/^/    /'
        echo ""
    fi

    local moon_list
    moon_list=$(fetch_moon_list)

    # Graceful fallback if the API is unreachable or rate-limited (60 req/hr unauthenticated)
    if [[ -z "$moon_list" ]]; then
        echo "Warning: could not fetch the moon list (offline, repo moved, or GitHub API rate limit)."
        read -p "Fall back to the default moon ($FALLBACK_MOON)? (Y/n): " USE_FALLBACK
        if [[ "$USE_FALLBACK" =~ ^[Nn] ]]; then
            return 1
        fi
        moon_list="$FALLBACK_MOON"
    fi

    # Build "added_date|path" records (one API call per moon file)
    local records="" path added_date sort_key disp_key
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        printf '  found %s' "$path"
        added_date=$(fetch_moon_added_date "$path")
        if [[ -n "$added_date" ]]; then
            sort_key="$added_date"
            disp_key="${added_date%%T*}"          # trim to YYYY-MM-DD for display
        else
            sort_key="0000-00-00"
            disp_key="unknown"
        fi
        records+="${sort_key}|${path}"$'\n'
        echo " (added: $disp_key)"
    done <<< "$moon_list"

    # Sort newest -> oldest so the newest moon is on top and recommended
    local sorted
    sorted=$(printf '%s\n' "$records" | grep -v '^$' | sort -t'|' -k1,1r -s)

    echo ""
    echo "Available moons (newest first):"
    local choices=() i=1 tag suffix
    while IFS='|' read -r added path; do
        tag=""
        suffix=""
        [[ $i -eq 1 ]] && tag="   <-- recommended"
        sudo test -f "$MOONS_DIR/$path" 2>/dev/null && suffix=" [already installed]"
        printf '  %2d) %-30s (added %s)%s%s\n' "$i" "$path" "$added" "$suffix" "$tag"
        choices+=("$path")
        i=$((i + 1))
    done <<< "$sorted"

    local count=${#choices[@]}
    echo ""
    local choice
    read -p "Select a moon to install (1-$count) [Enter = recommended]: " choice
    choice="${choice//[[:space:]]/}"
    [[ -z "$choice" ]] && choice=1
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
        echo "Invalid selection."
        return 1
    fi

    local selected="${choices[$((choice - 1))]}"

    echo ""
    echo "Downloading $selected ..."
    local tmp
    tmp=$(mktemp) || return 1
    if ! curl -fsSL --max-time 60 "$RAW_BASE/$selected" -o "$tmp" || [[ ! -s "$tmp" ]]; then
        echo "Error: failed to download the moon file."
        rm -f "$tmp"
        return 1
    fi

    sudo mkdir -p "$MOONS_DIR"
    if sudo test -f "$MOONS_DIR/$selected"; then
        echo "Note: $selected already exists and will be replaced."
    fi
    sudo mv "$tmp" "$MOONS_DIR/$selected"
    echo "Installed: $MOONS_DIR/$selected"
    return 0
}

echo "========================================"
echo "    ZeroTier Network Setup Script"
echo "========================================"
echo "0.5. What would you like to do?"
echo "  1) Install and configure ZeroTier"
echo "  2) Add a Moon"
echo "  3) Add a continuous ping service"
read -p "Please select an option (1/2/3): " MENU_OPTION

# ==============================================================================
# OPTION 1: FULL INSTALLATION
# ==============================================================================
if [[ "$MENU_OPTION" == "1" ]]; then
    # 1. Install ZeroTier
    if ! command -v zerotier-cli &> /dev/null; then
        echo "Which OS are you using?"
        echo "  1) Debian/Ubuntu"
        echo "  2) Arch/CachyOS"
        read -p "Select OS (1/2): " OS_OPTION

        if [[ "$OS_OPTION" == "1" ]]; then
            curl -s https://install.zerotier.com | sudo bash
        elif [[ "$OS_OPTION" == "2" ]]; then
            sudo pacman -S --needed zerotier-one
        else
            echo "Invalid OS option. Exiting."
            exit 1
        fi
    else
        echo "ZeroTier is already installed, skipping installation..."
    fi

    # 3. Enable the zerotier-one service
    echo "Enabling zerotier-one service..."
    sudo systemctl enable --now zerotier-one

    # 2. Join a network
    read -p "Join the default network (a581878f7d3719c2)? (Y/n): " JOIN_DEFAULT
    if [[ "$JOIN_DEFAULT" =~ ^[Nn] ]]; then
        read -p "Enter custom network ID: " NET_ID
    else
        NET_ID="a581878f7d3719c2"
    fi

    sudo zerotier-cli join "$NET_ID"

    echo ""
    echo "=========================================================="
    echo "⚠️  ACTION REQUIRED: Tell Мартин to authorize this device!"
    echo "=========================================================="
    read -p "Wait until he does so, then press Enter to continue..."

    # 4. Verify peers
    sudo zerotier-cli listpeers
    read -p "Do you see a good output of the command above? (yes/no): " PEERS_GOOD

    # 5. UFW configuration
    echo "Enabling ZeroTier in UFW..."
    sudo ufw allow in on ztfl6lbfv7 comment 'ZeroTier VPN'
    sudo ufw allow 9993/udp comment 'ZeroTier Direct P2P'

    # Flow smoothly into the Moon step
    echo ""
    read -p "Do you want to add a moon now? (y/n): " ADD_MOON_NOW
    if [[ "$ADD_MOON_NOW" =~ ^[Yy] ]]; then
        MENU_OPTION="2"
    else
        MENU_OPTION="3" # Skip moon, ask about service
    fi
fi

# ==============================================================================
# OPTION 2: ADD A MOON
# ==============================================================================
if [[ "$MENU_OPTION" == "2" ]]; then
    # 6. Check ZT, list moons from GitHub, let user pick, download, restart, verify
    check_zt_installed

    if [[ "$ADD_MOON_NOW" == "" ]]; then
        read -p "Do you want to add a moon? (y/n): " PROMPT_MOON
        if [[ "$PROMPT_MOON" =~ ^[Nn] ]]; then
            echo "Setup completed successfully! Enjoy your secure connection."
            exit 0
        fi
    fi

    echo "Adding Moon..."
    # Browse repo -> user picks a moon (newest recommended) -> download -> install
    if ! install_moon; then
        echo "Moon installation did not complete — continuing with the rest of the setup."
    fi

    # 2. Restart ZeroTier
    echo "Restarting ZeroTier service..."
    sudo systemctl restart zerotier-one
    sleep 2 # Give it a brief moment to find peers before listing

    # 3. Verify changes
    # 7. List peers and verify MOON
    sudo zerotier-cli listpeers
    read -p "Do you see a peer with 'MOON' at the end (yes/no)? " MOON_VERIFIED

    # Move to the continuous ping step smoothly
    MENU_OPTION="3"
fi

# ==============================================================================
# OPTION 3: ADD CONTINUOUS PING SERVICE
# ==============================================================================
if [[ "$MENU_OPTION" == "3" ]]; then
    # 8. Check ZT, explain service, prompt
    check_zt_installed

    echo ""
    echo "A continuous ping service sends an ICMP packet periodically (every 20s)."
    echo "This forces your ZeroTier tunnel to stay \"awake\" and prevents NAT firewalls"
    echo "from closing the UDP connection due to inactivity."
    read -p "Do you want to install a continuous ping service? (y/n): " INSTALL_PING

    if [[ "$INSTALL_PING" =~ ^[Nn] ]]; then
        # 10. Paste ending line
        echo "Setup completed successfully! Enjoy your secure connection."
        exit 0
    fi

    # 9. Install the service
    echo "Installing zt-keepalive.service..."
    sudo tee /etc/systemd/system/zt-keepalive.service > /dev/null << 'EOF' && sudo systemctl daemon-reload && sudo systemctl enable --now zt-keepalive
[Unit]
Description=ZeroTier Keepalive Ping
After=zerotier-one.service network-online.target
Wants=zerotier-one.service network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ping -i 20 10.6.37.69
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # 10. Paste ending line
    echo ""
    echo "Setup completed successfully! Enjoy your secure connection."
fi
