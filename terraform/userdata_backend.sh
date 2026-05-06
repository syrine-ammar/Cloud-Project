#!/bin/bash
set -e
exec > /var/log/userdata.log 2>&1

echo "=== Starting backend setup ==="

# Install Node.js 20
dnf update -y
dnf install -y git
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

echo "=== Node version: $(node --version) ==="

# Clone repo
cd /home/ec2-user
git clone ${repo_url} app
cd app/backend

echo "=== Repo cloned, writing .env ==="

# Write .env — no indentation so dotenv parses correctly
cat > /home/ec2-user/app/backend/.env << EOF
USE_JSON_STORAGE=false
DB_HOST=${db_host}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
PORT=3000
EOF

# Install production dependencies only
npm install --production

echo "=== npm install done, creating systemd service ==="

# Create systemd service
cat > /etc/systemd/system/backend.service << EOF
[Unit]
Description=Node.js Backend
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app/backend
ExecStart=/usr/bin/node /home/ec2-user/app/backend/index.js
Restart=on-failure
RestartSec=10
EnvironmentFile=/home/ec2-user/app/backend/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable backend
systemctl start backend

echo "=== Backend service started ==="