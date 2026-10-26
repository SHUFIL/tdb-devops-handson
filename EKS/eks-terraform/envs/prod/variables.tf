variable "region"      { type = string }
variable "environment" { type = string }

variable "vpc_cidr"             { type = string }
variable "azs"                  { type = list(string) }
variable "public_subnet_cidrs"  { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "single_nat_gateway"   { type = bool }

variable "cluster_version"        { type = string }
variable "endpoint_public_access" { type = bool }
variable "public_access_cidrs"    { type = list(string) }

variable "node_instance_types" { type = list(string) }
variable "node_capacity_type"  { type = string }
variable "node_disk_size"      { type = number }
variable "node_desired_size"   { type = number }
variable "node_min_size"       { type = number }
variable "node_max_size"       { type = number }
