terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dr]
    }
  }
}

locals {
  dr_enabled = var.enable_dr_replica
}

# =====================================================================
# KMS keys (one per region - cross-region replicas of encrypted DBs
# must be re-encrypted with a key that lives in the destination region)
# =====================================================================
resource "aws_kms_key" "primary" {
  description             = "${var.name} RDS primary"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = var.tags
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "dr" {
  provider                = aws.dr
  count                   = local.dr_enabled ? 1 : 0
  description             = "${var.name} RDS DR replica"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = var.tags
}

resource "aws_kms_alias" "dr" {
  provider      = aws.dr
  count         = local.dr_enabled ? 1 : 0
  name          = "alias/${var.name}-rds-dr"
  target_key_id = aws_kms_key.dr[0].key_id
}

# =====================================================================
# Primary region: networking
# =====================================================================
resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-rds-sg"
  description = "Postgres access for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

# count (not for_each): SG ids may be unknown until apply
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from allowed SG"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count             = length(var.allowed_cidr_blocks)
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "Postgres from allowed CIDR"
}

# =====================================================================
# Primary instance
#  - master password generated + stored + auto-rotated by RDS in
#    Secrets Manager (manage_master_user_password)
#  - automated backups, 7-day retention, auto-expire afterwards
#  - deletion protection off, no final snapshot, backups removed on destroy
# =====================================================================
resource "aws_db_instance" "primary" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.primary.arn

  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]
  publicly_accessible    = false

  # ---- backups ----
  backup_retention_period  = var.backup_retention_days
  backup_window            = "20:00-21:00"            # UTC
  maintenance_window       = "sun:21:30-sun:22:30"    # UTC, must not overlap backup window
  copy_tags_to_snapshot    = true
  delete_automated_backups = true

  # ---- teardown behaviour ----
  deletion_protection = var.deletion_protection
  skip_final_snapshot = true
  apply_immediately   = true

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = var.tags

  lifecycle {
    ignore_changes = [engine_version] # minor upgrades happen automatically
  }
}

# =====================================================================
# Same-region read replica (optional)
# =====================================================================
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = "${var.name}-postgres-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.instance_class

  storage_encrypted      = true
  kms_key_id             = aws_kms_key.primary.arn
  vpc_security_group_ids = [aws_security_group.primary.id]
  publicly_accessible    = false

  backup_retention_period  = 0
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = true
  apply_immediately        = true
  auto_minor_version_upgrade = true

  tags = var.tags

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# =====================================================================
# Cross-region DR replica (optional)
# =====================================================================
resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  count      = local.dr_enabled ? 1 : 0
  name       = "${var.name}-db-dr"
  subnet_ids = var.dr_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "dr" {
  provider    = aws.dr
  count       = local.dr_enabled ? 1 : 0
  name        = "${var.name}-rds-dr-sg"
  description = "Postgres access for ${var.name} DR replica"
  vpc_id      = var.dr_vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds-dr-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "dr_from_cidr" {
  provider          = aws.dr
  count             = local.dr_enabled ? length(var.dr_allowed_cidr_blocks) : 0
  security_group_id = aws_security_group.dr[0].id
  cidr_ipv4         = var.dr_allowed_cidr_blocks[count.index]
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "Postgres from DR VPC"
}

resource "aws_db_instance" "dr_replica" {
  provider = aws.dr
  count    = local.dr_enabled ? 1 : 0

  identifier          = "${var.name}-postgres-dr"
  replicate_source_db = aws_db_instance.primary.arn # ARN => cross-region
  instance_class      = coalesce(var.dr_instance_class, var.instance_class)

  storage_encrypted = true
  kms_key_id        = aws_kms_key.dr[0].arn

  multi_az               = var.dr_multi_az
  db_subnet_group_name   = aws_db_subnet_group.dr[0].name
  vpc_security_group_ids = [aws_security_group.dr[0].id]
  publicly_accessible    = false

  backup_retention_period  = var.backup_retention_days
  copy_tags_to_snapshot    = true
  delete_automated_backups = true

  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = true
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = var.tags

  lifecycle {
    ignore_changes = [engine_version]
  }
}
