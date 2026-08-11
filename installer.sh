#!/usr/bin/env bash

# Helper function to check if ZeroTier is installed
check_zt_installed() {
    if ! command -v zerotier-cli &> /dev/null; then
        echo "Error: ZeroTier is not installed on this system."
        echo "Please run the script again and select the installation option first."
        exit 1
    fi
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

    # 3. Enable the zerotier-one service (Moved up slightly so we can join)
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
    # 6. Check ZT, prompt to join moon, download, move, restart, verify
    check_zt_installed
    
    if [[ "$ADD_MOON_NOW" == "" ]]; then
        read -p "Do you want to add a moon? (y/n): " PROMPT_MOON
        if [[ "$PROMPT_MOON" =~ ^[Nn] ]]; then
            echo "Setup completed successfully! Enjoy your secure connection."
            exit 0
        fi
    fi

    echo "Adding Moon..."
    # 1. Download the file
    sudo mkdir -p /var/lib/zerotier-one/moons.d/
    echo "Running SCP (You might be asked for the host password/key)..."
    scp -P 42069 bread@31.56.180.192:/home/bread/0000005f38c5d870.moon ~/
    sudo mv ~/0000005f38c5d870.moon /var/lib/zerotier-one/moons.d/
    
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
ExecStart=/usr/bin/ping -i 20 10.6.37.251
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 10. Paste ending line
    echo ""
    echo "Setup completed successfully! Enjoy your secure connection."
fi
