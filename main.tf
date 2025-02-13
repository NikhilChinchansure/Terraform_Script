provider "aws" {
  region     = var.aws_region
  access_key = ""
  secret_key = ""
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name               = "${var.project_name}-vpc"
  cidr               = "10.0.0.0/16"
  azs                = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway = true
}

# Security Groups
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.project_name}-eks-cluster-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for EKS cluster"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

resource "aws_security_group" "worker_nodes_sg" {
  name        = "${var.project_name}-worker-nodes-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for EKS worker nodes"

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for Application Load Balancer"

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
}

# EKS Cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "19.19.0"
  cluster_name    = "${var.project_name}-eks"
  cluster_version = "1.25"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = { # Fixed: Changed `node_groups` to `eks_managed_node_groups`
    worker_nodes = {
      desired_size                  = 2
      max_size                      = 3
      min_size                      = 1
      instance_types                = ["t3.medium"]
      additional_security_group_ids = [aws_security_group.worker_nodes_sg.id]
    }
  }

  cluster_security_group_id = aws_security_group.eks_cluster_sg.id
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
}

# Using aws_iam_role_policy to attach an policy to the role
resource "aws_iam_role_policy" "eks_cluster_policy" {
  name   = "eks-cluster-policy"
  role   = aws_iam_role.eks_cluster_role.id
  policy = data.aws_iam_policy_document.eks_policy.json
}

data "aws_iam_policy_document" "eks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eks_policy" {
  statement {
    actions   = ["ec2:*", "ecr:*", "eks:*", "autoscaling:*"]
    resources = ["*"]
  }
}

# Assuming you need to use this policy for another role, otherwise consider removing it if not used
data "aws_iam_policy_document" "alb_controller" {
  statement {
    actions   = ["elasticloadbalancing:*", "ec2:*", "iam:PassRole", "logs:*"]
    resources = ["*"]
  }
}