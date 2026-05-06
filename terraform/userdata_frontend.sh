#!/bin/bash
set -e
exec > /var/log/userdata.log 2>&1

echo "=== Starting frontend setup ==="

dnf update -y
dnf install -y git nginx

# Clone repo
cd /home/ec2-user
git clone ${repo_url} app

echo "=== Finding built Angular files ==="

# Try Angular 17+ path first (dist/project/browser/)
DIST_DIR=$(find /home/ec2-user/app/client/dist -name "browser" -type d 2>/dev/null | head -1)

# Fall back to Angular 16 path (dist/project/)
if [ -z "$DIST_DIR" ]; then
  DIST_DIR=$(find /home/ec2-user/app/client/dist -mindepth 1 -maxdepth 1 -type d | head -1)
fi

echo "=== Copying from $DIST_DIR ==="
cp -r $DIST_DIR/* /usr/share/nginx/html/

echo "=== Injecting ALB URL into compiled JS ==="
# sed runs on the compiled JS files in nginx root — not the .ts source
grep -rl "ALB_DNS_PLACEHOLDER" /usr/share/nginx/html/ | while read file; do
  sed -i "s|ALB_DNS_PLACEHOLDER|http://${alb_dns}|g" "$file"
  echo "Replaced in: $file"
done

# Verify replacement worked
echo "=== Verifying replacement ==="
grep -r "ALB_DNS_PLACEHOLDER" /usr/share/nginx/html/ && echo "WARNING: placeholder still found!" || echo "Replacement successful"

# Nginx config
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

rm -f /etc/nginx/conf.d/default.conf
systemctl enable nginx
systemctl start nginx

echo "=== Frontend setup complete ==="