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

# ---------------- DR-region VPC (isolated, DB subnets only) ----------------
module "vpc_dr" {
  count     = var.enable_dr_replica ? 1 : 0
  source    = "../../modules/vpc"
  providers = { aws = aws.dr }

  name                 = "${local.name}-dr"
  cluster_name         = "${local.cluster_name}-dr"
  vpc_cidr             = var.dr_vpc_cidr
  azs                  = var.dr_azs
  public_subnet_cidrs  = []
  private_subnet_cidrs = var.dr_private_subnet_cidrs
  enable_nat_gateway   = false
}

# ---------------- PostgreSQL RDS ----------------
module "rds" {
  source    = "../../modules/rds"
  providers = { aws = aws, aws.dr = aws.dr }

  name       = local.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Only the EKS nodes can talk to the DB
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection

  create_read_replica = var.db_create_read_replica

  enable_dr_replica      = var.enable_dr_replica
  dr_vpc_id              = var.enable_dr_replica ? module.vpc_dr[0].vpc_id : null
  dr_subnet_ids          = var.enable_dr_replica ? module.vpc_dr[0].private_subnet_ids : []
  dr_allowed_cidr_blocks = [var.dr_vpc_cidr]
}
