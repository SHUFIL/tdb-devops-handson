locals {
  name         = "eks-${var.environment}"
  cluster_name = "eks-${var.environment}"
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_disk_size      = var.node_disk_size
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}
