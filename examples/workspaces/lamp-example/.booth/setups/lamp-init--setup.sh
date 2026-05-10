#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Workspace-local setup for the LAMP example:
# - Installs the php-mysql extension so PHP can talk to MySQL.
# - Drops the example index.php into /var/www/html.
# - Adds a startup hook that creates a `lamp_demo` database with one row.

set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends php-mysql
rm -rf /var/lib/apt/lists/*

# Replace the default Apache landing page.
rm -f /var/www/html/index.html

cat >/var/www/html/index.php <<'PHP'
<?php
$user = getenv('USER') ?: 'coder';
$mysqli = new mysqli('localhost', $user, '', 'lamp_demo');
if ($mysqli->connect_errno) {
    http_response_code(500);
    echo "<h1>LAMP example — DB not ready yet</h1>";
    echo "<p>" . htmlspecialchars($mysqli->connect_error) . "</p>";
    exit;
}
$row = $mysqli->query("SELECT message FROM hello LIMIT 1")->fetch_assoc();
?>
<!doctype html>
<html><body style="font-family:system-ui;padding:2rem">
  <h1>Hello from LAMP in CodingBooth!</h1>
  <p>Apache served this page, PHP rendered it, MySQL gave us this row:</p>
  <blockquote><strong><?= htmlspecialchars($row['message']) ?></strong></blockquote>
</body></html>
PHP
chown -R www-data:www-data /var/www/html

# Startup hook: ensure DB and seed row exist once mysqld is up.
STARTUP_FILE="/usr/share/startup.d/60-cb-lamp--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail
for i in $(seq 1 30); do
  mysqladmin ping --silent 2>/dev/null && break
  sleep 1
done

mysql -u root <<SQL 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS lamp_demo;
USE lamp_demo;
CREATE TABLE IF NOT EXISTS hello (id INT AUTO_INCREMENT PRIMARY KEY, message VARCHAR(255));
INSERT INTO hello (message) SELECT 'Hi from MySQL!' WHERE NOT EXISTS (SELECT 1 FROM hello);
SQL
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ LAMP demo ready: index.php + lamp_demo database with one row."
