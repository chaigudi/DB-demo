output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for the cluster-autoscaler service account."
  value       = module.irsa_cluster_autoscaler.iam_role_arn
}

output "scylla_s3_role_arn" {
  description = "IRSA role ARN to annotate on the scylla-member service account."
  value       = module.irsa_scylla_s3.iam_role_arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA."
  value       = module.eks.oidc_provider_arn
}
