#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Prompt the user for the SSH public key
echo "Please enter the SSH public key:"
read -r SSH_PUBLIC_KEY

# The SSH_PUBLIC_KEY variable now contains the user input

# Define the configuration file path
CONF_FILE="/etc/ssh/sshd_config.d/block_pwd.conf"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Create or overwrite the configuration file to disable password authentication
echo "Creating $CONF_FILE to block password authentication via SSH"
{
    echo "# Block password authentication"
    echo "PasswordAuthentication no"
} > "$CONF_FILE"

# Restart the SSH service to apply changes
echo "Restarting SSH service to apply changes"
systemctl restart sshd

echo "Password authentication has been disabled."

# Add Docker's official GPG key and set up the repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl software-properties-common
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and other necessary packages
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin dbus-user-session uidmap

# Disable system Docker if it's enabled
if systemctl is-active --quiet docker; then
  sudo systemctl disable --now docker
  echo "Docker service has been disabled."
else
  echo "Docker service is not active, no need to disable."
fi

# Configure sysctl for unprivileged Docker
if [ ! -f /etc/sysctl.d/docker_unprivilege.conf ]; then
  echo "net.ipv4.ip_unprivileged_port_start=0" | sudo tee /etc/sysctl.d/docker_unprivilege.conf
  sudo sysctl --system
else
  echo "/etc/sysctl.d/docker_unprivilege.conf already exists."
fi

# Check for the existence of user account dockeract
if ! id -u dockeract > /dev/null 2>&1; then
sudo adduser --disabled-password --gecos "" dockeract
  sudo mkdir -p /home/dockeract/.ssh
  echo "$SSH_PUBLIC_KEY" | sudo tee /home/dockeract/.ssh/authorized_keys
  sudo chown -R dockeract:dockeract /home/dockeract/.ssh
  sudo chmod 700 /home/dockeract/.ssh
  sudo chmod 600 /home/dockeract/.ssh/authorized_keys
  echo "User dockeract created and configured."
else
  echo "User dockeract already exists. Updating SSH public keys."
  echo "$SSH_PUBLIC_KEY" | sudo tee -a /home/dockeract/.ssh/authorized_keys
fi

# Enable linger for dockeract
if ! loginctl show-user dockeract | grep -q "Linger=yes"; then
  sudo loginctl enable-linger dockeract
  echo "Linger has been enabled for dockeract."
else
  echo "Linger is already enabled for dockeract."
fi

#creating container data directory
mkdir -p /opt/contdata/
chown -R dockeract:dockeract /opt/contdata/
chmod 770 /opt/contdata/

# Add necessary environment variables to dockeract's .bashrc
sudo -u dockeract bash -c 'echo "
# Set Docker rootless mode environment variables
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export PATH=/usr/bin:\$PATH
export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/docker.sock
" >> ~/.bashrc'

sleep 10

sudo -u dockeract XDG_RUNTIME_DIR=/run/user/$(id -u dockeract) DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus /usr/bin/dockerd-rootless-setuptool.sh install

sudo -u dockeract XDG_RUNTIME_DIR=/run/user/$(id -u dockeract) DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus systemctl --user enable docker

echo "Docker has been installed and configured for user dockeract."

echo "===================="

echo "switching to user dockeract"
su - dockeract

echo "Script execution completed."