variable "name" { type = string }

# ---- primary region networking ----
variable "vpc_id"     { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" {
  description = "SGs allowed to reach Postgres (e.g. EKS cluster SG)"
  type        = list(string)
  default     = []
}
variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

# ---- engine / sizing ----
variable "engine_version" {
  description = "Postgres major (e.g. 16) - RDS picks the latest minor"
  type        = string
  default     = "16"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (0 disables)"
  type        = number
  default     = 100
}
variable "db_name" {
  type    = string
  default = "appdb"
}
variable "master_username" {
  type    = string
  default = "dbadmin"
}

# ---- HA / backup / lifecycle ----
variable "multi_az" {
  description = "Synchronous standby in another AZ (in-region HA)"
  type        = bool
  default     = false
}
variable "backup_retention_days" {
  type    = number
  default = 7
}
variable "deletion_protection" {
  type    = bool
  default = false
}

# ---- replication ----
variable "create_read_replica" {
  description = "Same-region read replica (read scaling)"
  type        = bool
  default     = false
}

variable "enable_dr_replica" {
  description = "Cross-region read replica (disaster recovery)"
  type        = bool
  default     = false
}
variable "dr_vpc_id" {
  type    = string
  default = null
}
variable "dr_subnet_ids" {
  type    = list(string)
  default = []
}
variable "dr_allowed_cidr_blocks" {
  type    = list(string)
  default = []
}
variable "dr_instance_class" {
  description = "Defaults to the primary instance class"
  type        = string
  default     = null
}
variable "dr_multi_az" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
