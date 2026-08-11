### Installation & setup
> [!WARNING]
> **Prerequisite Warning:**
> This assumes that you have created a network on the zerotier.com site.
#### Automatic Installation (not tested)


#### Manual Installation
1. Depending on OS, either run 
> Arch:
```bash
sudo pacman -S zerotier-one
```
> Ubuntu:
```bash
# Ubuntu
curl -s https://install.zerotier.com | sudo bash
```
> Windows:
```
google it idk
```

2. Join a network and start the zerotier service
```bash
sudo zerotier-cli join a581878f7d3719c2
sudo systemctl enable --now zerotier-one
```
3. List peers, to verify if you joined the network. To find out your ZT ip, look in the admin panel on the zerotier website.
```bash
sudo zerotier-cli listpeers
```
4. Enable zerotier-one in the firewall (ufw)
```bash
sudo ufw allow in on ztfl6lbfv7 comment 'ZeroTier VPN'
sudo ufw allow 9993/udp comment 'ZeroTier Direct P2P'
```
### Creating & joining a moon
		I do not know how to do this for windows.
#### Creating the moon
1. [[#Installation & setu|Install zerotier on the VPS]]
2. Switch to root and generate the moon.json
```bash
# Switch to root for permission stuff
sudo su
# Generate moon.json
cd /var/lib/zerotier-one
zerotier-idtool initmoon identity.public > moon.json
```
3. Edit moon.json to modify the stable endpoints, making it point to the vps IP (Don't forget to enable firewall!)
	moon.json:
```json
"stableEndpoints": [ "31.56.180.192/9993" ]
```
4. Generate the .moon file:
```bash
zerotier-idtool genmoon moon.json
```
You will see a message like:
```text
Zerotier moon:
wrote 0000005f38c5d870.moon (signed world with timestamp 1786438785613)
```
#### Joining the moon
1. Add the moon to your PC:
```bash
# 1. Download the file
sudo mkdir /var/lib/zerotier-one/moons.d/
scp -P 42069 bread@31.56.180.192:/home/bread/0000005f38c5d870.moon ~
sudo mv ~/0000005f38c5d870.moon /var/lib/zerotier-one/moons.d/
# 2. Restart ZeroTier:
sudo systemctl restart zerotier-one
```
2. Verify changes:
```bash
sudo zerotier-cli listpeers
# Should have an output with MOON at the end.
# 200 listpeers 5f38c5d870 31.56.180.192/41765;2770;2692 138 1.16.2 MOON
```

### Continuous VPS ping
To ensure that zerotier is always active from boot, make a service which pings the VPS's zerotier IP. This is completely optional, and I am *not* sure that it does anything at all. Follow these instructions, or open a bash shell and paste the script.
#### Manual installation
1. Create the service file
```bash
sudo nano /etc/systemd/system/zt-keepalive.service
```
2. Paste this configuration
```ini
[Unit]
Description=ZeroTier Keepalive Ping
After=zerotier-one.service network-online.target
Wants=zerotier-one.service network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ping -i 20 <VPS_ZEROTIER_IP>
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```
3. Start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now zt-keepalive
```
#### Bash script
		Run in bash!
```bash
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
```
