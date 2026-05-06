#!/bin/bash
set -e
exec > /var/log/userdata.log 2>&1

echo "=== Starting frontend setup ==="

# Install dependencies
dnf update -y
dnf install -y git nginx
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

echo "=== Node version: $(node --version) ==="

# Install Angular CLI
npm install -g @angular/cli --unsafe-perm

# Clone repo
cd /home/ec2-user
git clone ${repo_url} app
cd app/client

echo "=== Injecting ALB URL: ${alb_dns} ==="

# Replace placeholder with real ALB DNS
sed -i "s|ALB_DNS_PLACEHOLDER|http://${alb_dns}|g" \
  src/environments/environment.prod.ts

# Verify the replacement worked
grep "apiUrl" src/environments/environment.prod.ts

npm install

echo "=== Building Angular app ==="
ng build --configuration=production

# Handle both Angular 16 (dist/project/) and 17+ (dist/project/browser/)
echo "=== dist folder contents ==="
find dist -type d

# Try browser subfolder first (Angular 17+), fall back to project root (Angular 16)
DIST_DIR=$(find dist -name "browser" -type d 2>/dev/null | head -1)
if [ -z "$DIST_DIR" ]; then
  DIST_DIR=$(find dist -mindepth 1 -maxdepth 1 -type d | head -1)
fi

echo "=== Copying from $DIST_DIR to nginx root ==="
cp -r $DIST_DIR/* /usr/share/nginx/html/

# Nginx config with Angular routing support
cat > /etc/nginx/conf.d/angular.conf << EOF
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# Remove default nginx config to avoid conflict
rm -f /etc/nginx/conf.d/default.conf

systemctl enable nginx
systemctl start nginx

echo "=== Frontend setup complete ==="