# Quantspark tech test 11/23 Tim Collie

# Create VPC
resource "aws_vpc" "quantspark_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {"Name" = "QuantsparkApp"}
  )
}

# Create public subnets
resource "aws_subnet" "quantspark_public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.quantspark_vpc.id
  cidr_block        = element(["10.0.0.0/24", "10.0.1.0/24"], count.index)
  availability_zone = element(["eu-west-2a", "eu-west-2b"], count.index)
  map_public_ip_on_launch = true
  tags = merge(
    var.tags,
    {Name = "QuantsparkApp-public-subnet-${count.index}"}
  )
}

# Create private subnets
resource "aws_subnet" "quantspark_private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.quantspark_vpc.id
  cidr_block        = element(["10.0.2.0/24", "10.0.3.0/24"], count.index)
  availability_zone = element(["eu-west-2a", "eu-west-2b"], count.index)
  map_public_ip_on_launch = false
  tags = merge(
    var.tags,
    {Name = "QuantsparkApp-private-subnet-${count.index}"}
  )
}

# Create IGW
resource "aws_internet_gateway" "quantspark_igw" {
  vpc_id = aws_vpc.quantspark_vpc.id

  tags = merge(
    var.tags,
    {Name = "QuantsparkIGW"}
  )
}

# Attach IGW
resource "aws_route" "quantspark_igw_attachment" {
  count                  = 2
  route_table_id         = aws_vpc.quantspark_vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.quantspark_igw.id
}

# S3 endpoint to allow EC2 updates
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.quantspark_vpc.id
  service_name = "com.amazonaws.eu-west-2.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_route_table_assoc" {
  route_table_id = aws_vpc.quantspark_vpc.main_route_table_id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_policy" "s3_endpoint_policy" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement": [
      {
        "Principal": "*",
        "Action": [
          "s3:GetObject"
        ],
        "Effect": "Allow",
        "Resource": [
          "arn:aws:s3:::al2023-repos-eu-west-2-de612dc2/*"
        ]
      }
    ]
  })
}

# Generate SSH key
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name = "quantspark-webserver"
  public_key = tls_private_key.key_pair.public_key_openssh
}

# Store ssh key in Secrets Manager
resource "aws_secretsmanager_secret" "ssh_secret" {
  name = "ssh-keys/quantspark-webserver-private-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "secretsmanager_secret" {
  secret_id     = aws_secretsmanager_secret.ssh_secret.id
  secret_string = tls_private_key.key_pair.private_key_pem
}


# Create ALB security group
resource "aws_security_group" "quantspark_alb_security_group" {
  name        = "alb-quantspark-webserver-sg"
  description = "ALB webserver security group"
  vpc_id      = aws_vpc.quantspark_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Create ALB
resource "aws_lb" "quantspark_alb" {
  name               = "alb-quantspark-webserver"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.quantspark_public_subnets[*].id
  enable_deletion_protection = false
  security_groups = [aws_security_group.quantspark_alb_security_group.id]

  tags = var.tags
}

# Create ALB target group
resource "aws_lb_target_group" "quantspark_webserver_target_group" {
  name     = "quantspark-ws-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.quantspark_vpc.id

  tags = var.tags
}

# Create listener on port 80
resource "aws_lb_listener" "quantspark_webserver_alb_listener" {
  load_balancer_arn = aws_lb.quantspark_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.quantspark_webserver_target_group.arn
    type             = "forward"
  }

  tags = var.tags
}

# Create ASG IAM role
resource "aws_iam_role" "quantspark_asg_role" {
  name = "QuantSparkASGRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "autoscaling.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Create instance profile
resource "aws_iam_instance_profile" "quantspark_asg_instance_profile" {
  name = "ASGInstanceProfile"
  role = aws_iam_role.quantspark_asg_role.name
}

# Create webserver security group
resource "aws_security_group" "quantspark_webserver_security_group" {
  name        = "quantspark-webserver-sg"
  description = "webserver security group"
  vpc_id      = aws_vpc.quantspark_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #cidr_blocks = ["10.0.0.0/16"]
    security_groups = [aws_security_group.quantspark_alb_security_group.id]
  }

  tags = var.tags
}

# Create launch template
resource "aws_launch_template" "quantspark_webserver" {
  name_prefix = "quantspark-webserver-"
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      delete_on_termination = true
      volume_type = "gp2"
    }
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups = [aws_security_group.quantspark_webserver_security_group.id]
  }
  instance_type = "t2.micro"
  image_id      = "ami-0cfd0973db26b893b"
  user_data = filebase64("./user_data.sh")
  key_name = "quantspark-webserver"
}

# Create autoscaling group
resource "aws_autoscaling_group" "quantspark_asg" {
  name = "Quantspark-asg"
  vpc_zone_identifier = aws_subnet.quantspark_private_subnets[*].id
  target_group_arns  = [aws_lb_target_group.quantspark_webserver_target_group.arn]
  min_size           = 2
  max_size           = 2
  desired_capacity   = 2

  launch_template {
    id      = aws_launch_template.quantspark_webserver.id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

}




