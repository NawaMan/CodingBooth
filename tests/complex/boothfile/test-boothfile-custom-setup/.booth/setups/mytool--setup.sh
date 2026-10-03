#!/bin/bash
# Custom setup script for testing

# Create a marker file to prove this script ran
echo "MYTOOL_INSTALLED" > /tmp/mytool-marker.txt

# Create a simple "command" in /usr/local/bin
cat > /usr/local/bin/mytool << 'SCRIPT'
#!/bin/bash
echo "mytool version 1.0.0 - custom setup works!"
SCRIPT
chmod +x /usr/local/bin/mytool

# Set an environment variable via profile
cat > /etc/profile.d/70-cb-mytool--profile.sh << 'PROFILE'
export MYTOOL_HOME=/opt/mytool
PROFILE
