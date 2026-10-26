output "primary_endpoint" { value = aws_db_instance.primary.address }
output "primary_port"     { value = aws_db_instance.primary.port }
output "db_name"          { value = aws_db_instance.primary.db_name }
output "security_group_id" { value = aws_security_group.primary.id }

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the auto-rotated master credentials"
  value       = aws_db_instance.primary.master_user_secret[0].secret_arn
}

output "read_replica_endpoint" {
  value = var.create_read_replica ? aws_db_instance.read_replica[0].address : null
}

output "dr_replica_endpoint" {
  value = local.dr_enabled ? aws_db_instance.dr_replica[0].address : null
}

output "dr_replica_arn" {
  value = local.dr_enabled ? aws_db_instance.dr_replica[0].arn : null
}
