terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

#AWS provider to deploy the resources in the us-west-2 (london) region.
provider "aws" {
  region = "eu-west-2"
}

# The image the instances will use
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

# Create a Virtual Private Cloud with cidr_block: 10.0.0.0/16 
resource "aws_vpc" "k8s_vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = "true" #gives you an internal domain name
    enable_dns_hostnames = "true" #gives you an internal host name
    instance_tenancy = "default"    
    
    tags = {
        Name = "k8s_vpc"
    }
}

# Public Subnet in the VPC above 
resource "aws_subnet" "k8s_subnet" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.k8s_vpc.cidr_block, 4, 3)
  map_public_ip_on_launch = true #it makes this a public subnet
}

# Internet Gateway that enables the vpc to connect to the internet
resource "aws_internet_gateway" "k8s_igw" {
    vpc_id = aws_vpc.k8s_vpc.id
    tags = {
        Name = "k8s_igw"
    }
}

# A custom route table for the public subnet to reach the internet.
resource "aws_route_table" "k8s_public_rt" {
    vpc_id = aws_vpc.k8s_vpc.id
    
    route {
        cidr_block = "0.0.0.0/0" 
        gateway_id = aws_internet_gateway.k8s_igw.id
    }
    
    tags = {
        Name = "k8s_public_rt"
    }
}

# Associate the custom route table and subnet
resource "aws_route_table_association" "k8s_rt_public_subnet"{
    subnet_id = aws_subnet.k8s_subnet.id
    route_table_id = aws_route_table.k8s_public_rt.id
}

# Security group to allow ssh port (for ansible to access the instances) and the Kubernetes ports to open
resource "aws_security_group" "allow_k8s" {
  name        = "allow_k8s"
  description = "Allow Kube-api-server, kubelet etc"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "Kubernetes API server"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
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
    Name = "allow_k8s"
  }
}

#Network interface to attach to the instances with the subnet and security group
resource "aws_network_interface" "k8s_network" {
  subnet_id   = aws_subnet.k8s_subnet.id
  security_groups = [aws_security_group.allow_k8s.id]
  count = 3
  tags = {
    Name = "primary_network_interface"
  }
}

#Create 3 EC2 instances ( 1 control node, 2 worker nodes) 
resource "aws_instance" "k8s_master_ec2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.medium"
  key_name = "server"
  count = 3
#  associate_public_ip_address = "true"

  network_interface {
    network_interface_id = aws_network_interface.k8s_network[count.index].id
    device_index         = 0
  }

  tags = {
    Name = "k8s_master"
  }
}

# Template file function to read the inventory template and populate the public ip addresses of the instances.
locals {

inventory = templatefile(
		"${path.module}/inventory.tp",
               {
                 ip_addresses = aws_instance.k8s_master_ec2.*.public_ip
               }
              )

}

#copy the final template contents into inventory.yaml file
resource "local_file" "ansible_inventory" {
    content  = local.inventory
    filename = "inventory.yaml"
}