#!/bin/bash

set -e
set -o pipefail

# Install Command Line Tools
if [[ ! -x /usr/bin/gcc ]]; then
  echo "[INFO] Install macOS Command Line Tools"
  xcode-select --install
fi

# Install Homebrew
if [[ ! -x /usr/local/bin/brew ]]; then
  echo "[INFO] Install Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install Ansible
if [[ ! -x /usr/local/bin/ansible ]]; then
  echo "[INFO] Install Ansible"
  brew install ansible
fi

# Create workspace directory in home directory
if [[ ! -d ~/Workspace ]]; then
  echo "[INFO] Create workspace directory in home directory"
  mkdir -p ~/Workspace
fi

# Checkout Git repository
if [[ ! -d ~/Workspace/ansible-setup ]]; then
  echo "[INFO] Clone ansible-setup in workspace folder"
  git clone https://github.com/quentinpigne/ansible-setup ~/Workspace/ansible-setup
fi

echo "[INFO] Done"
exit 0
