terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67"
    }
  }
}

provider "aws" {
  region = var.region
}

# ══════════════════════════════════════════
# DATA SOURCES
# ══════════════════════════════════════════

# Latest Amazon Linux 2023 — lighter & faster than Ubuntu for Node.js
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Pre-created Vocareum IAM profile — we can't create our own
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# ══════════════════════════════════════════
# VPC
# ══════════════════════════════════════════

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "project-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "project-igw" }
}

# ── Public subnets (ALB + NAT + frontend EC2)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-b" }
}

# ── Private subnets (backend EC2 ASG + RDS)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.region}b"
  tags              = { Name = "private-b" }
}

# ── NAT Gateway (lets private EC2s reach internet to run git clone & npm install)
resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "project-nat" }
}

# ── Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ══════════════════════════════════════════
# SECURITY GROUPS
# ══════════════════════════════════════════

# ALB — only HTTP from internet
resource "aws_security_group" "alb" {
  name        = "sg-alb"
  description = "ALB: HTTP from internet only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-alb" }
}

# Backend EC2 — only from ALB security group on port 3000
resource "aws_security_group" "backend" {
  name        = "sg-backend"
  description = "Backend: traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Node.js from ALB only"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-backend" }
}

# RDS MySQL — only from backend EC2 security group
resource "aws_security_group" "rds" {
  name        = "sg-rds"
  description = "RDS: MySQL only from backend EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from backend only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-rds" }
}

# Frontend EC2 — HTTP + SSH from internet
resource "aws_security_group" "frontend" {
  name        = "sg-frontend"
  description = "Frontend: HTTP from internet, SSH for debug"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for debugging only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-frontend" }
}

# ══════════════════════════════════════════
# RDS — MySQL
# ══════════════════════════════════════════

resource "aws_db_subnet_group" "rds" {
  name       = "project-rds-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "rds-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier             = "project-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = { Name = "project-mysql" }
}

# ══════════════════════════════════════════
# ALB + TARGET GROUP + LISTENER
# ══════════════════════════════════════════

resource "aws_lb" "backend" {
  name               = "project-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = { Name = "project-alb" }
}

resource "aws_lb_target_group" "backend" {
  name     = "project-backend-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    port                = "3000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }

  tags = { Name = "project-backend-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ══════════════════════════════════════════
# BACKEND — Launch Template + ASG
# ══════════════════════════════════════════

resource "aws_launch_template" "backend" {
  name_prefix   = "project-backend-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t2.micro"

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.backend.id]
  }

  # base64encode() is required — EC2 User Data must be base64
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # ── Install Node.js 20 on Amazon Linux 2023
    dnf update -y
    dnf install -y git

    # nodesource setup for Amazon Linux 2023
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    dnf install -y nodejs

    # ── Clone backend
    cd /home/ec2-user
    git clone ${var.repo_url} app
    cd app/backend 

    # ── Write .env file from Terraform variables
    # This is how we pass secrets without hardcoding them in code
    cat > .env << 'ENVFILE'
    USE_JSON_STORAGE=false
    DB_HOST=${aws_db_instance.mysql.address}
    DB_USER=${var.db_username}
    DB_PASSWORD=${var.db_password}
    DB_NAME=${var.db_name}
    PORT=3000
    ENVFILE

    # ── Install dependencies
    npm install --production

    # ── Run with systemd so it restarts on crash automatically
    cat > /etc/systemd/system/backend.service << 'SERVICE'
    [Unit]
    Description=Node.js Backend
    After=network.target

    [Service]
    Type=simple
    User=ec2-user
    WorkingDirectory=/home/ec2-user/app
    ExecStart=/usr/bin/node index.js
    Restart=on-failure
    RestartSec=10
    EnvironmentFile=/home/ec2-user/app/.env
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable backend
    systemctl start backend
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "backend-ec2" }
  }
}

resource "aws_autoscaling_group" "backend" {
  name                = "project-backend-asg"
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  target_group_arns   = [aws_lb_target_group.backend.arn]

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "backend-asg-instance"
    propagate_at_launch = true
  }
}

# CPU scaling policy — scale out when average CPU > 70%
resource "aws_autoscaling_policy" "cpu" {
  name                   = "cpu-scale-policy"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ══════════════════════════════════════════
# FRONTEND — Angular EC2 in public subnet
# ══════════════════════════════════════════

resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  associate_public_ip_address = true
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── Install Node.js 20 + Nginx
    dnf update -y
    dnf install -y git nginx

    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    dnf install -y nodejs

    # ── Install Angular CLI globally
    npm install -g @angular/cli --unsafe-perm

    # ── Clone Angular frontend
    cd /home/ec2-user
    git clone ${var.repo_url} app
    cd app/client

    # ── Inject real ALB URL into the environment file before building
    # This replaces the placeholder we set in Step 0
    sed -i "s|ALB_DNS_PLACEHOLDER|http://${aws_lb.backend.dns_name}|g" \
      src/environments/environment.prod.ts

    # ── Install deps and build for production
    npm install
    ng build --configuration=production

    # Angular outputs to dist/<project-name>/browser — copy to nginx root
    # The project name is usually the folder name in dist/
    DIST_DIR=$(find dist -mindepth 2 -maxdepth 2 -type d | head -1)
    cp -r $DIST_DIR/* /usr/share/nginx/html/

    # ── Configure Nginx
    # Default config serves /usr/share/nginx/html — no changes needed
    # But we add try_files for Angular's client-side routing
    cat > /etc/nginx/conf.d/angular.conf << 'NGINXCONF'
    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }
    }
    NGINXCONF

    # Disable the default nginx config to avoid port conflict
    rm -f /etc/nginx/conf.d/default.conf

    systemctl enable nginx
    systemctl start nginx
  EOF

  # Wait for RDS and ALB to be ready — their values are needed in this script
  depends_on = [aws_db_instance.mysql, aws_lb.backend]

  tags = { Name = "frontend-ec2" }
}