#!/bin/bash

echo "Install docker"

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

systemctl enable --now docker

echo "Deploy jenkins container"

echo "Check network firewall"


# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or using sudo."
  exit 1
fi

PORTS=("8080" "50000")
FIREWALL_UPDATED=false

# Check for UFW (Ubuntu/Debian)
if command -v ufw &> /dev/null && systemctl is-active --quiet ufw; then
    echo "Detected active UFW firewall. Opening ports..."
    for port in "${PORTS[@]}"; do
        ufw allow "$port"/tcp > /dev/null
    done
    ufw reload > /dev/null
    FIREWALL_UPDATED=true

# Check for firewalld (RHEL/Rocky Linux/Fedora)
elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    echo "Detected active Firewalld. Opening ports..."
    for port in "${PORTS[@]}"; do
        firewall-cmd --permanent --add-port="$port"/tcp > /dev/null
    done
    firewall-cmd --reload > /dev/null
    FIREWALL_UPDATED=true
fi

# Final Output Logic
if [ "$FIREWALL_UPDATED" = true ]; then
    echo "From firewall side 8080 and 50000 ports are open"
else
    echo "No active firewall (UFW/Firewalld) detected on this host. Skipping configuration."
    echo "From firewall side 8080 and 50000 ports are open"
fi


mkdir ./jenkins_home

docker run -d   -p 8080:8080   -p 50000:50000   --user root   -v ./jenkins_home:/var/jenkins_home   --name jenkins-server   --restart unless-stopped   jenkins/jenkins:lts

ip_jenkins=$(hostname -I | awk '{print $1}')


echo "Install git"

# Check if Git is already installed
if command -v git &> /dev/null; then
    echo "Git is already installed: $(git --version)"
    exit 0
fi

echo "Git is not installed. Detecting package manager..."

# Check for apt (Debian, Ubuntu, Mint, Pop!_OS)
if command -v apt &> /dev/null; then
    echo "Detected APT package manager."
    sudo apt update && sudo apt install -y git

# Check for dnf (Fedora, RHEL 8+, Rocky Linux)
elif command -v dnf &> /dev/null; then
    echo "Detected DNF package manager."
    sudo dnf install -y git

# Check for yum (Older RHEL, CentOS 7)
elif command -v yum &> /dev/null; then
    echo "Detected YUM package manager."
    sudo yum install -y git

# Check for pacman (Arch Linux, Manjaro)
elif command -v pacman &> /dev/null; then
    echo "Detected Pacman package manager."
    sudo pacman -Syu --noconfirm git

# Check for zypper (openSUSE)
elif command -v zypper &> /dev/null; then
    echo "Detected Zypper package manager."
    sudo zypper refresh && sudo zypper install -y git

# Check for apk (Alpine Linux)
elif command -v apk &> /dev/null; then
    echo "Detected APK package manager."
    sudo apk add --update git

else
    echo "Error: No supported package manager found (apt, dnf, yum, pacman, zypper, apk)."
    echo "Please install Git manually for your distribution."
    exit 1
fi

# Verify installation
if command -v git &> /dev/null; then
    echo "Git installed successfully: $(git --version)"
else
    echo "Installation failed. Please check your system logs."
    exit 1
fi

echo "Install terraform"

#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Terraform installer for Linux
# Installs Terraform under:
#   $HOME/.local/bin
#
# No sudo required.
#
# Current stable version verified from HashiCorp:
#   Terraform 1.16.4
# ============================================================

TERRAFORM_VERSION="1.16.4"

INSTALL_DIR="${HOME}/.local/bin"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=============================================="
echo " Terraform Installation"
echo " Version : ${TERRAFORM_VERSION}"
echo " Install : ${INSTALL_DIR}"
echo "=============================================="

# ------------------------------------------------------------
# Check required commands
# ------------------------------------------------------------

for cmd in curl unzip sha256sum; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo
        echo "ERROR: Required command '$cmd' is not installed."
        echo
        echo "Please install it using your Linux distribution's package manager."
        exit 1
    fi
done

# ------------------------------------------------------------
# Detect CPU architecture
# ------------------------------------------------------------

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        TERRAFORM_ARCH="amd64"
        ;;
    aarch64|arm64)
        TERRAFORM_ARCH="arm64"
        ;;
    armv7l|armv6l)
        TERRAFORM_ARCH="arm"
        ;;
    s390x)
        TERRAFORM_ARCH="s390x"
        ;;
    i386|i686)
        TERRAFORM_ARCH="386"
        ;;
    *)
        echo "ERROR: Unsupported CPU architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: ${ARCH}"
echo "Terraform architecture: ${TERRAFORM_ARCH}"

# ------------------------------------------------------------
# Download Terraform
# ------------------------------------------------------------

ZIP_FILE="terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip"
BASE_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"

echo
echo "Downloading:"
echo "${BASE_URL}/${ZIP_FILE}"

curl -fL \
    "${BASE_URL}/${ZIP_FILE}" \
    -o "${TMP_DIR}/${ZIP_FILE}"

# ------------------------------------------------------------
# Download official SHA256SUMS
# ------------------------------------------------------------

echo
echo "Downloading checksum file..."

curl -fL \
    "${BASE_URL}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
    -o "${TMP_DIR}/SHA256SUMS"

# ------------------------------------------------------------
# Verify checksum
# ------------------------------------------------------------

echo
echo "Verifying Terraform checksum..."

cd "$TMP_DIR"

EXPECTED_CHECKSUM="$(
    grep " ${ZIP_FILE}$" SHA256SUMS | awk '{print $1}'
)"

if [[ -z "$EXPECTED_CHECKSUM" ]]; then
    echo "ERROR: Could not find checksum for ${ZIP_FILE}"
    exit 1
fi

ACTUAL_CHECKSUM="$(
    sha256sum "${ZIP_FILE}" | awk '{print $1}'
)"

echo "Expected : ${EXPECTED_CHECKSUM}"
echo "Actual   : ${ACTUAL_CHECKSUM}"

if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
    echo
    echo "ERROR: Checksum verification FAILED."
    exit 1
fi

echo "Checksum verification successful."

# ------------------------------------------------------------
# Extract
# ------------------------------------------------------------

unzip -oq "${ZIP_FILE}" -d "$TMP_DIR"

if [[ ! -f "${TMP_DIR}/terraform" ]]; then
    echo "ERROR: terraform binary was not found after extraction."
    exit 1
fi

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

mkdir -p "$INSTALL_DIR"

install -m 0755 \
    "${TMP_DIR}/terraform" \
    "${INSTALL_DIR}/terraform"

# ------------------------------------------------------------
# Configure PATH
# ------------------------------------------------------------

PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

add_path_to_file() {
    local file="$1"

    if [[ -f "$file" ]] && ! grep -Fqx "$PATH_LINE" "$file"; then
        echo "$PATH_LINE" >> "$file"
        echo "Added PATH configuration to $file"
    fi
}

add_path_to_file "${HOME}/.bashrc"
add_path_to_file "${HOME}/.bash_profile"
add_path_to_file "${HOME}/.profile"

export PATH="${INSTALL_DIR}:${PATH}"

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

echo
echo "=============================================="
echo "Terraform installed successfully"
echo "=============================================="

"${INSTALL_DIR}/terraform" version

echo
echo "Terraform location:"
command -v terraform || echo "${INSTALL_DIR}/terraform"

echo
echo "If 'terraform' isn't found in a new shell, run:"
echo
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
echo

echo "Install Ansible"



# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or using sudo."
  exit 1
fi

# Check if Ansible is already installed
if command -v ansible &> /dev/null; then
    echo "Ansible is already installed: $(ansible --version | head -n 1)"
    exit 0
fi

echo "Ansible is not installed. Detecting system environment..."

# Check for apt (Ubuntu, Debian, Mint)
if command -v apt &> /dev/null; then
    echo "Detected Ubuntu/Debian family."
    apt update
    # Ubuntu requires software-properties-common for PPA
    if command -v add-apt-repository &> /dev/null || apt install -y software-properties-common; then
        echo "Adding Ansible PPA..."
        add-apt-repository --yes --update ppa:ansible/ansible
    fi
    apt install -y ansible

# Check for dnf (Fedora, RHEL 8+, Rocky Linux, AlmaLinux)
elif command -v dnf &> /dev/null; then
    echo "Detected RedHat/Fedora family (DNF)."
    # RHEL/Rocky/Alma need EPEL repository first
    if ! dnf list installed epel-release &> /dev/null; then
        echo "Installing EPEL repository..."
        dnf install -y epel-release
    fi
    dnf install -y ansible

# Check for pacman (Arch Linux, Manjaro)
elif command -v pacman &> /dev/null; then
    echo "Detected Arch Linux family."
    pacman -Syu --noconfirm ansible

# Check for zypper (openSUSE)
elif command -v zypper &> /dev/null; then
    echo "Detected openSUSE family."
    zypper refresh
    zypper install -y ansible

# Fallback to Python Pip if no system package manager matches
elif command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
    echo "No native package manager match found. Falling back to Python Pip..."
    PIP_CMD=$(command -v pip3 || command -v pip)
    $PIP_CMD install --upgrade pip
    $PIP_CMD install ansible

else
    echo "Error: No supported package manager or Python environment found."
    echo "Please install Python3 and Pip, or install Ansible manually."
    exit 1
fi

# Verify installation
if command -v ansible &> /dev/null; then
    echo "Ansible installed successfully: $(ansible --version | head -n 1)"
else
    echo "Installation failed. Please check the logs."
    exit 1
fi

echo "Git , Docker , Ansible ,  Terraform and Jenkins are installed"

echo "You can access the jenkins UI from local browser using the  url : http://$ip_jenkins:8080"
