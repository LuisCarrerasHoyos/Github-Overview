##########################################################
# 1️⃣ Obtener las zonas de disponibilidad disponibles
##########################################################
data "aws_availability_zones" "available" {
  state = "available"
}

##########################################################
# 2️⃣ Crear la VPC principal
##########################################################
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr  # "10.0.0.0/16"
  
  tags = {
    Name = "wordpress-vpc-luis"
  }
}

##########################################################
# 3️⃣ Crear Internet Gateway (para subredes públicas)
##########################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wordpress-igw"
  }
}

##########################################################
# 4️⃣ Crear subredes públicas
##########################################################
resource "aws_subnet" "public" {
  for_each = {
    az1 = var.public_subnet_cidrs[0]  # CIDR de primera subred pública
    az2 = var.public_subnet_cidrs[1]  # CIDR de segunda subred pública
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[(each.key == "az1" ? 0 : 1)]
  map_public_ip_on_launch = true  # Las instancias recibirán IP pública automáticamente

  tags = {
    Name = "public-subnet-${each.key}"
  }
}

##########################################################
# 5️⃣ Crear subredes privadas (para RDS)
##########################################################
resource "aws_subnet" "private" {
  for_each = {
    az1 = var.private_subnet_cidrs[0]
    az2 = var.private_subnet_cidrs[1]
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[(each.key == "az1" ? 0 : 1)]
  map_public_ip_on_launch = false  # Sin IP pública

  tags = {
    Name = "private-subnet-${each.key}"
  }
}

##########################################################
# 6️⃣ Crear tabla de rutas para subredes públicas
##########################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Asociar tabla de rutas a subredes públicas
resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

##########################################################
# 7️⃣ Crear NAT Gateway (para subredes privadas)
##########################################################
# Elastic IP para NAT
resource "aws_eip" "nat" {
  domain = "vpc"  # Sintaxis corregida para EIP en VPC
}

# NAT Gateway en la primera subred pública
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["az1"].id  # Referencia corregida

  tags = {
    Name = "nat-gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Tabla de rutas para subredes privadas
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

# Asociar tabla de rutas privadas a subredes privadas
resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

##########################################################
# 8️⃣ Security Groups
##########################################################

# ALB: permite HTTP/HTTPS desde cualquier IP
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# ASG: permite HTTP/HTTPS desde ALB y SSH desde cualquier IP
resource "aws_security_group" "asg_sg" {
  name        = "asg-sg"
  description = "Allow HTTP/HTTPS from ALB, SSH from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
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

  tags = {
    Name = "asg-sg"
  }
}

# RDS: solo permite conexión Postgres desde ASG
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow Postgres from ASG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.asg_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

##########################################################
# 9️⃣ Clave SSH para las instancias
##########################################################
resource "aws_key_pair" "main" {
  key_name   = "terraform-key-${var.environment}"
  public_key = var.public_key
}

##########################################################
# 10️⃣ Buscar AMI de Ubuntu para las instancias web
##########################################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##########################################################
# 11️⃣ Generar contraseña segura para RDS
##########################################################
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

##########################################################
# 12️⃣ Launch Template para ASG
##########################################################
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.small"
  key_name      = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.asg_sg.id]  # Sintaxis corregida

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-web-instance"
      Role = "web"     
      Environment = "production"
    }
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y nginx
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>Hello from ASG instance</h1>" > /var/www/html/index.html
              EOF
  )
}

##########################################################
# 13️⃣ Application Load Balancer
##########################################################
resource "aws_lb" "web_alb" {
  name               = "web-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]  # Sintaxis corregida

  tags = {
    Name = "web-alb-${var.environment}"
  }
}

# Target group del ALB
resource "aws_lb_target_group" "web_tg" {
  name        = "web-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener del ALB
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

##########################################################
# 14️⃣ AutoScaling Group (CORREGIDO)
##########################################################
resource "aws_autoscaling_group" "web_asg" {
  name_prefix          = "web-asg-luis-"
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = [for subnet in aws_subnet.public : subnet.id]  # Solo esto
  
  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.web_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"

  # Instancias distribuidas en diferentes AZs automáticamente
  tag {
    key                 = "Name"
    value               = "asg-web-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "web"
    propagate_at_launch = true  # ✅ ESTO ES CRUCIAL
  }

  tag {
    key                 = "Environment"
    value               = "production" 
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

##########################################################
# 15️⃣ RDS PostgreSQL (Usuario Corregido)
##########################################################
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group-${var.environment}"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = "rds-subnet-group-${var.environment}"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "wordpress-db-luis"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  db_name                = "wordpress"
  username               = "wordpress_user"  # Usuario cambiado
  password               = random_password.db_password.result
  allocated_storage      = 20
  max_allocated_storage  = 20
  storage_type           = "gp2"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot    = true
  multi_az               = false
  publicly_accessible    = false
  backup_retention_period = 1
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  tags = {
    Name = "wordpress-database"
  }

  depends_on = [aws_db_subnet_group.rds_subnet_group]
}
