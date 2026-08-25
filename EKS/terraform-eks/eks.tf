module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.system_instance_type]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      subnet_ids     = module.vpc.private_subnets
    }

    scylla = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.scylla_instance_type]
      min_size       = var.scylla_min_nodes
      max_size       = var.scylla_max_nodes
      desired_size   = var.scylla_min_nodes
      subnet_ids     = module.vpc.private_subnets

      labels = {
        "scylla.scylladb.com/node-pool" = "scylla"
      }

      iam_role_additional_policies = {
        scylla_s3 = aws_iam_policy.scylla_s3.arn
      }

      taints = {
        dedicated = {
          key    = "scylla.scylladb.com/dedicated"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.scylla_root_disk_gib
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }
  node_security_group_additional_rules = {
    scylla_operator_webhook = {
      description                   = "EKS control plane to scylla-operator webhook"
      protocol                      = "tcp"
      from_port                     = 5000
      to_port                       = 5000
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}
