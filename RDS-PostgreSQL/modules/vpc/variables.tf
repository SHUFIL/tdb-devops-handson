variable "name"                 { type = string }
variable "cluster_name"         { type = string }
variable "vpc_cidr"             { type = string }
variable "azs"                  { type = list(string) }
variable "public_subnet_cidrs"  { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }

variable "single_nat_gateway" {
  description = "true = one NAT for all AZs (cheap, dev). false = one NAT per AZ (HA, prod)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_nat_gateway" {
  description = "false = no NAT/EIP (isolated private subnets, e.g. DB-only DR VPC)"
  type        = bool
  default     = true
}
