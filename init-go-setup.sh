#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# init-go-setup.sh - Install Go programming language
#
# This script downloads and installs the specified version of Go (currently 1.24.1)
# for Linux and macOS systems. It detects the OS and architecture automatically,
# downloads the appropriate Go distribution, verifies it, and configures the PATH.
# The script is idempotent and will skip installation if the correct version exists.
#
set -euo pipefail

GO_VERSION="1.24.1"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_TARBALL}"

echo "🚀 Go ${GO_VERSION} Setup Script"
echo "================================"
echo ""

# Detect OS
OS_TYPE="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="mac"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

echo "📋 Detected OS: $OS_TYPE"

# Check if Go is already installed and at the correct version
if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    if [[ "$CURRENT_VERSION" == "$GO_VERSION" ]]; then
        echo "✅ Go ${GO_VERSION} is already installed"
        go version
        exit 0
    else
        echo "⚠️  Go is installed but version is ${CURRENT_VERSION}, not ${GO_VERSION}"
        echo "   Proceeding with installation of Go ${GO_VERSION}..."
    fi
else
    echo "📦 Go is not installed. Installing Go ${GO_VERSION}..."
fi

echo ""

# Platform-specific installation
if [[ "$OS_TYPE" == "linux" ]]; then
    echo "🐧 Installing Go ${GO_VERSION} on Linux..."
    
    # Determine package manager
    if command -v apt-get &> /dev/null; then
        PKG_MGR="apt"
    elif command -v yum &> /dev/null; then
        PKG_MGR="yum"
    else
        echo "❌ Neither apt nor yum found. Please install Go manually."
        exit 1
    fi
    
    # Determine architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        GO_ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        GO_ARCH="arm64"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    
    GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    GO_DOWNLOAD_URL="https://go.dev/dl/${GO_TARBALL}"
    
    echo "   Architecture: ${GO_ARCH}"
    echo "   Package Manager: ${PKG_MGR}"
    echo "   Download URL: ${GO_DOWNLOAD_URL}"
    echo ""
    
    # Download Go
    echo "📥 Downloading Go ${GO_VERSION}..."
    cd /tmp
    curl -LO "$GO_DOWNLOAD_URL"
    
    # Remove old Go installation if it exists
    if [[ -d "/usr/local/go" ]]; then
        echo "🗑️  Removing old Go installation..."
        sudo rm -rf /usr/local/go
    fi
    
    # Extract Go
    echo "📦 Extracting Go..."
    sudo tar -C /usr/local -xzf "$GO_TARBALL"
    
    # Clean up
    rm "$GO_TARBALL"
    
    # Add to PATH if not already there
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo "🔧 Adding Go to PATH in ~/.bashrc..."
        echo "" >> ~/.bashrc
        echo "# Go ${GO_VERSION}" >> ~/.bashrc
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
    fi
    
    # Also add to current session
    export PATH=$PATH:/usr/local/go/bin
    
elif [[ "$OS_TYPE" == "mac" ]]; then
    echo "🍎 Installing Go ${GO_VERSION} on macOS..."
    
    # Determine architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        GO_ARCH="amd64"
    elif [[ "$ARCH" == "arm64" ]]; then
        GO_ARCH="arm64"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    
    GO_TARBALL="go${GO_VERSION}.darwin-${GO_ARCH}.tar.gz"
    GO_DOWNLOAD_URL="https://go.dev/dl/${GO_TARBALL}"
    
    echo "   Architecture: ${GO_ARCH}"
    echo "   Download URL: ${GO_DOWNLOAD_URL}"
    echo ""
    
    # Download Go
    echo "📥 Downloading Go ${GO_VERSION}..."
    cd /tmp
    curl -LO "$GO_DOWNLOAD_URL"
    
    # Remove old Go installation if it exists
    if [[ -d "/usr/local/go" ]]; then
        echo "🗑️  Removing old Go installation..."
        sudo rm -rf /usr/local/go
    fi
    
    # Extract Go
    echo "📦 Extracting Go..."
    sudo tar -C /usr/local -xzf "$GO_TARBALL"
    
    # Clean up
    rm "$GO_TARBALL"
    
    # Add to PATH if not already there
    SHELL_RC="$HOME/.zshrc"
    if [[ ! -f "$SHELL_RC" ]]; then
        SHELL_RC="$HOME/.bashrc"
    fi
    
    if ! grep -q "/usr/local/go/bin" "$SHELL_RC"; then
        echo "🔧 Adding Go to PATH in ${SHELL_RC}..."
        echo "" >> "$SHELL_RC"
        echo "# Go ${GO_VERSION}" >> "$SHELL_RC"
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "$SHELL_RC"
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$SHELL_RC"
    fi
    
    # Also add to current session
    export PATH=$PATH:/usr/local/go/bin
fi

echo ""
echo "✅ Go ${GO_VERSION} installation complete!"
echo ""
echo "🔍 Verifying installation..."
/usr/local/go/bin/go version

echo ""
echo "📝 Note: You may need to restart your shell or run:"
echo "   source ~/.bashrc    (Linux)"
echo "   source ~/.zshrc     (macOS)"
echo ""
echo "🎉 Setup complete!"
