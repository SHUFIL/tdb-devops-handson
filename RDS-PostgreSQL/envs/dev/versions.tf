terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "eks-platform"
    }
  }
}

# Second region for the cross-region DB replica
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "eks-platform"
    }
  }
}
