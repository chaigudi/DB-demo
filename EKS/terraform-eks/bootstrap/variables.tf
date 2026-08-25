variable "region" {
  description = "AWS region for the state bucket and lock table."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
  default     = "chaithu-scylla-tfstate"
}

variable "lock_table_name" {
  description = "DynamoDB table name used for state locking."
  type        = string
  default     = "scylla-assessment-tf-lock"
}
