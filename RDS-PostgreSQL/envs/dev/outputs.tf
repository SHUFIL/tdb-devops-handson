output "cluster_name"     { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id"           { value = module.vpc.vpc_id }
output "kubeconfig_cmd" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "db_endpoint"           { value = module.rds.primary_endpoint }
output "db_secret_arn"         { value = module.rds.master_user_secret_arn }
output "db_read_replica"       { value = module.rds.read_replica_endpoint }
output "db_dr_replica"         { value = module.rds.dr_replica_endpoint }
