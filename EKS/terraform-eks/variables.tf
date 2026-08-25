variable "region" {
  description = "AWS region with at least three Availability Zones."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "scylla-assessment"
}

variable "kubernetes_version" {
  description = "EKS control-plane Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "scylla_instance_type" {
  description = "EBS-backed, memory-optimized instance type for ScyllaDB nodes."
  type        = string
  default     = "r6i.xlarge"
}

variable "scylla_min_nodes" {
  description = "Minimum ScyllaDB nodes."
  type        = number
  default     = 3
}

variable "scylla_max_nodes" {
  description = "Maximum ScyllaDB nodes."
  type        = number
  default     = 5
}

variable "scylla_root_disk_gib" {
  description = "Root EBS volume size per ScyllaDB node in GiB. Data lives on separate PVCs."
  type        = number
  default     = 50
}

variable "system_instance_type" {
  description = "Instance type for the operator, manager, cert-manager and autoscaler."
  type        = string
  default     = "m6i.large"
}

variable "s3_backup_bucket" {
  description = "S3 bucket name ScyllaDB Manager backs up to."
  type        = string
  default     = "chaithu-scylla-backups"
}
