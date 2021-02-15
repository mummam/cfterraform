terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Subnet 1 
# Internet Facing 
# Availability_zone: us-east-1a
resource "aws_subnet" "sub1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Sub1"
  }
}

# Subnet 2 
# Internet Facing 
# Availability_zone: us-east-1b
resource "aws_subnet" "sub2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "Sub2"
  }
}

# Subnet 3
# Internal Facing 
# Availability_zone: us-east-1a
resource "aws_subnet" "sub3" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Sub3"
  }
}

# Subnet 4
# Internal Facing
# Availability_zone: us-east-1b
resource "aws_subnet" "sub4" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Sub4"
  }
}

# Internet Gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
      Name = "main"
  }
}

# Route Tables Public and Private
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route" "igw" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  depends_on = [aws_route_table.public]
}

resource "aws_route" "nat" {
  route_table_id = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.gw_a.id
  depends_on = [aws_route_table.private]
}

resource "aws_route_table_association" "public_sub1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_sub2" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat_gateway_a" {
  vpc = true
}


resource "aws_nat_gateway" "gw_a" {
  allocation_id = aws_eip.nat_gateway_a.id
  subnet_id = aws_subnet.sub1.id
  
  depends_on = [aws_internet_gateway.igw]
}

# Instance in Sub1 Logic / Security Group
# Generalized Security group not scoped or specified just listening to VPC 
resource "aws_security_group" "web_group" {
  name        = "web_group"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Web tier"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web_group"
  }
}

# SSH to machine 
# To be replaced if I implement ssm which requires an iam role
# Which would be the prefered way to connect to this for the screenshot
resource "aws_security_group" "personal_ssh" {
  name        = "personal_ssh"
  description = "SSH from my pc"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Web tier"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["65.28.252.57/32"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "personal_ssh"
  }
}


resource "aws_network_interface" "public_eni" {
  subnet_id = aws_subnet.sub1.id
  security_groups = [aws_security_group.web_group.id, aws_security_group.personal_ssh.id]

  depends_on = [aws_security_group.web_group, aws_security_group.personal_ssh]
}

resource "aws_instance" "web" {
  ami           = "ami-096fda3c22c1c990a"
  instance_type = "t2.micro"
  key_name = "homekeypair"


  network_interface {
    network_interface_id = aws_network_interface.public_eni.id
    device_index = 0
  }
  root_block_device {
    volume_size = "20"
  }

  tags = {
      Name = "Web-server-sub1"
  }
}

# Instance in Sub3 Behind an ALB
resource "aws_security_group" "lb_group" {
  name        = "lb_group"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Internet web Traffic"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb_group"
  }
}

resource "aws_security_group" "private_apache_group" {
  name        = "private_apache_group"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Internet web Traffic"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.lb_group.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private_apache_group"
  }
}

resource "aws_network_interface" "private_eni" {
  subnet_id = aws_subnet.sub3.id
  security_groups = [aws_security_group.private_apache_group.id]

  depends_on = [aws_security_group.private_apache_group]
}

# Apache instance Sub3 with Load balancer pointed at it
# Update to load a file for user data instead of inside of here
resource "aws_instance" "apache" {
  ami           = "ami-096fda3c22c1c990a"
  instance_type = "t2.micro"
  key_name = "homekeypair"

  root_block_device {
    volume_size = "20"
  }

  network_interface {
    network_interface_id = aws_network_interface.private_eni.id
    device_index = 0
  }

 user_data =  "#!/bin/bash\nsudo yum install httpd -y\nsudo service httpd start\nsudo echo \"<html><h1>Hey Coalfire</h1></html>\" | sudo tee /var/www/html/index.html\n"

  tags = {
      Name = "apache-server-sub3"
  }
}

# ALB 
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.lb_group.id]
  # subnets = [aws_subnet.sub2.id, aws_subnet.sub3.id ]
  subnets = [aws_subnet.sub1.id, aws_subnet.sub2.id ]
}

# Target Group 
resource "aws_lb_target_group" "apache_targets" {
  name     = "apache-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Target Group attachment
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.apache_targets.arn
  target_id = aws_instance.apache.id
  port = 80
}

resource "aws_alb_listener" "front_end" {
    load_balancer_arn = aws_lb.web_alb.arn
    port = "80"
    protocol = "HTTP"
    default_action {
        target_group_arn = aws_lb_target_group.apache_targets.id
        type = "forward"
  }
}
