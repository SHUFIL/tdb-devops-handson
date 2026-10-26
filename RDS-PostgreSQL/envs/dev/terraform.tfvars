region      = "ap-south-1"
environment = "dev"

vpc_cidr             = "10.10.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
single_nat_gateway   = true   # cheaper for dev

cluster_version        = "1.31"
endpoint_public_access = true
public_access_cidrs    = ["0.0.0.0/0"]   # restrict to your IP in practice

node_instance_types = ["t3.medium"]
node_capacity_type  = "SPOT"
node_disk_size      = 20
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3

# ---------------- DR region (off in dev to save cost) ----------------
enable_dr_replica       = false
dr_region               = "ap-southeast-1"
dr_vpc_cidr             = "10.11.0.0/16"
dr_azs                  = ["ap-southeast-1a", "ap-southeast-1b"]
dr_private_subnet_cidrs = ["10.11.10.0/24", "10.11.11.0/24"]

# ---------------- Database ----------------
db_engine_version        = "16"
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_max_allocated_storage = 50
db_multi_az              = false
db_create_read_replica   = false
db_backup_retention_days = 7
db_deletion_protection   = false
