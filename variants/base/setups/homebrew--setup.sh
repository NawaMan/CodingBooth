#!/bin/bash
# cb-version: 1.0.0
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

apt-get update
apt-get install -y build-essential

function install-homebrew() {
    export NONINTERACTIVE=1
    # Staged to a file rather than run out of a command substitution. `bash -c
    # "$(curl ...)"` hides curl's exit status: a transfer that dies half way still
    # yields the bytes received so far, and bash runs that truncated installer as
    # if nothing were wrong. Downloading first makes a failed fetch a failed setup.
    local installer
    installer="$(mktemp)"
    if ! curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$installer" \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh; then
        echo "❌ Failed to download the Homebrew installer" >&2
        rm -f "$installer"
        return 1
    fi
    /bin/bash "$installer"
    rm -f "$installer"
}
sudo -u coder bash -c "$(declare -f install-homebrew); install-homebrew"

# Set up group permissions
groupadd linuxbrew
usermod -aG linuxbrew coder
chown -R root:linuxbrew /home/linuxbrew
chmod -R g+w /home/linuxbrew
find /home/linuxbrew -type d -exec chmod g+s {} \;

# Login shells read this via /etc/profile. Interactive non-login shells re-source
# only /etc/profile.d/*-cb-*.sh (booth-entry). `booth exec` reads neither — the
# homebrew template puts these bin dirs on the image PATH for that.
cat > /etc/profile.d/50-cb-homebrew--profile.sh << 'EOF'
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
EOF
chmod 644 /etc/profile.d/50-cb-homebrew--profile.sh