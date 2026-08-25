variable "github_repo" {
  description = "owner/repo allowed to assume the CI role."
  type        = string
  default     = "chaigudi/DB-demo"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "gha_scylla" {
  name               = "gha-scylla"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

data "aws_iam_policy_document" "gha_perms" {
  statement {
    sid       = "DescribeEKS"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_policy" "gha_perms" {
  name   = "gha-scylla-perms"
  policy = data.aws_iam_policy_document.gha_perms.json
}

resource "aws_iam_role_policy_attachment" "gha_perms" {
  role       = aws_iam_role.gha_scylla.name
  policy_arn = aws_iam_policy.gha_perms.arn
}

resource "aws_iam_role_policy_attachment" "gha_s3" {
  role       = aws_iam_role.gha_scylla.name
  policy_arn = aws_iam_policy.scylla_s3.arn
}

resource "aws_eks_access_entry" "gha_scylla" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.gha_scylla.arn
  type              = "STANDARD"
  kubernetes_groups = ["gha-scylla"]
}

output "gha_role_arn" {
  description = "Role ARN to put in the workflow's role-to-assume."
  value       = aws_iam_role.gha_scylla.arn
}
