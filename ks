#version=RHEL8
# Rocky Linux 8 - Minimal GNOME Kickstart
# Provides a clean GNOME shell without bloat + gnome-terminal

#------------------------------------------------------------------------------
# Installation Method
#------------------------------------------------------------------------------
graphical
# Use network install - replace URL with a local mirror if preferred
url --mirrorlist="https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=BaseOS-8"

#------------------------------------------------------------------------------
# System Settings
#------------------------------------------------------------------------------
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/New_York --isUtc
selinux --enforcing
firewall --enabled --service=ssh

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------
network --bootproto=dhcp --device=link --activate
network --hostname=localhost.localdomain

#------------------------------------------------------------------------------
# Users & Auth
#------------------------------------------------------------------------------
# Set root password (change this - generate with: python3 -c
# "import crypt; print(crypt.crypt('yourpassword', crypt.mksalt(crypt.METHOD_SHA512)))")
rootpw --iscrypted $6$CHANGEME

# Create a default user - change username and password hash as needed
user --name=admin --groups=wheel --iscrypted --password=$6$CHANGEME

#------------------------------------------------------------------------------
# Disk & Bootloader
#------------------------------------------------------------------------------
bootloader --append="rhgb quiet" --location=mbr
zerombr
clearpart --all --initlabel
autopart --type=lvm

#------------------------------------------------------------------------------
# Package Selection
#------------------------------------------------------------------------------
%packages
# Core base
@Base
@Core

# Minimal GNOME shell + display manager
gnome-shell
gdm

# Terminal
gnome-terminal

# Useful extras - comment out anything you don't want
gnome-tweaks
nautilus
gnome-control-center

# Optional but handy
bash-completion
wget
curl
vim-enhanced

# Explicitly exclude common bloat
-gnome-maps
-gnome-weather
-gnome-contacts
-gnome-calendar
-gnome-clocks
-gnome-photos
-totem
-rhythmbox
-cheese
-gnome-documents
-evolution
-gnome-tour
-gnome-boxes
-LibreOffice*
%end

#------------------------------------------------------------------------------
# Services
#------------------------------------------------------------------------------
%post
# Set graphical boot target
systemctl set-default graphical.target

# Enable GDM
systemctl enable gdm

# Disable Tracker (file indexer) - reduces background resource usage
sudo -u admin bash -c '
  mkdir -p ~/.config/systemd/user
  systemctl --user mask tracker-store.service \
                        tracker-miner-fs.service \
                        tracker-miner-rss.service \
                        tracker-extract.service \
                        tracker-writeback.service
'

# Disable GNOME Software automatic updates
systemctl disable --now packagekit
%end

#------------------------------------------------------------------------------
# Reboot after install
#------------------------------------------------------------------------------
reboot
