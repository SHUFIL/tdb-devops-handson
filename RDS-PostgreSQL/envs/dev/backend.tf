# Backend blocks cannot use variables - values are hardcoded.
# Bucket/table are created by ./bootstrap
terraform {
  backend "s3" {
    bucket         = "CHANGE-ME-tfstate-bucket"
    key            = "eks/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
