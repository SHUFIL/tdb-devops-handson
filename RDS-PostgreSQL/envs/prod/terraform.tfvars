region      = "ap-south-1"
environment = "prod"

vpc_cidr             = "10.20.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
single_nat_gateway   = false  # one NAT per AZ for HA

cluster_version        = "1.31"
endpoint_public_access = true
public_access_cidrs    = ["203.0.113.0/24"]   # REPLACE with office/VPN CIDR

node_instance_types = ["m5.large"]
node_capacity_type  = "ON_DEMAND"
node_disk_size      = 50
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 6

# ---------------- DR region (cross-region replica) ----------------
enable_dr_replica       = true
dr_region               = "ap-southeast-1"
dr_vpc_cidr             = "10.21.0.0/16"
dr_azs                  = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
dr_private_subnet_cidrs = ["10.21.10.0/24", "10.21.11.0/24", "10.21.12.0/24"]

# ---------------- Database ----------------
db_engine_version        = "16"
db_instance_class        = "db.m6g.large"
db_allocated_storage     = 100
db_max_allocated_storage = 500
db_multi_az              = true
db_create_read_replica   = false
db_backup_retention_days = 7
db_deletion_protection   = false   # as requested; set true for real prod
