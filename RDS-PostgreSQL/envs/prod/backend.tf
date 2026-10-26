terraform {
  backend "s3" {
    bucket         = "CHANGE-ME-tfstate-bucket"
    key            = "eks/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
