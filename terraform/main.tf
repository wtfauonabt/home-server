provider "aws" {
  region = "ap-east-1"  # Replace with your desired region
}

## Get the AMI of the ubuntu ami
data "aws_ami" "ubuntu_jammy" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "pi4_ssh_key" {
  key_name   = "pi4_ssh_key"
  public_key = file("~/.ssh/pi4.pub")
}

## Create the EC2 instance
resource "aws_instance" "home_tunnel_instance" {
  ami           = data.aws_ami.ubuntu_jammy.image_id
  instance_type = "t4g.micro"
  key_name      = aws_key_pair.pi4_ssh_key.key_name

  tags = {
    Name = "home_tunnel_instance"
    SystemManager = "true"
  }

  vpc_security_group_ids = [aws_security_group.home_tunnel_sg.id]

  user_data_base64 = base64encode("${templatefile("./user_data_script.sh", {
    BASE_DOMAIN         = var.domain_name
  })}")
}

## Create the Security Group to expose 80 and 443 ports
resource "aws_security_group" "home_tunnel_sg" {
  name        = "home_tunnel_sg"
  description = "Home Tunnel Security Group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3001
    to_port     = 3010
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# Elastic IP
## Create the elastic IP
resource "aws_eip" "home_tunnel_eip" {
  instance = aws_instance.home_tunnel_instance.id

  tags = {
    Name = "home_tunnel_eip"
  }
}

# Route53 Reocrds
## Get zone ID
data "aws_route53_zone" "home_tunnel_zone" {
  name = "${var.domain_name}."
}

## Create the required records
resource "aws_route53_record" "home_tunnel_record" {
  zone_id = data.aws_route53_zone.home_tunnel_zone.zone_id
  name    = "home.${var.domain_name}."
  type    = "A"
  ttl     = "300"

  records = [aws_eip.home_tunnel_eip.public_ip]
}

resource "aws_route53_record" "home_tunnel_wildcard_record" {
  zone_id = data.aws_route53_zone.home_tunnel_zone.zone_id
  name    = "*.home.${var.domain_name}."
  type    = "A"
  ttl     = "300"

  records = [aws_eip.home_tunnel_eip.public_ip]
}