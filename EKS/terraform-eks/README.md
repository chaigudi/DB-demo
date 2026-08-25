# EKS for ScyllaDB — Terraform

Spins up a production-minded EKS cluster sized to run a **3-to-5 node ScyllaDB cluster** with the ScyllaDB Operator, across 3 Availability Zones, with keyless S3 backup credentials (IRSA) and node autoscaling.

## What it creates

| Resource | Detail |
|---|---|
| VPC | 3 AZs, private + public subnets, 1 NAT gateway, autoscaler + ELB subnet tags |
| EKS cluster | v1.33, public API endpoint, OIDC/IRSA enabled |
| `system` node group | 2× `m6i.large`, untainted — operator, manager, cert-manager, autoscaler |
| `scylla` node group | `r6i.xlarge`, **min 3 / max 5**, tainted `scylla.scylladb.com/dedicated` |
| Addons | CoreDNS, kube-proxy, VPC CNI, Pod Identity agent, EBS CSI driver (IRSA) |
| IRSA roles | EBS CSI, Cluster Autoscaler, and a bucket-scoped ScyllaDB S3 backup role |
| Remote state | `bootstrap/` creates an S3 state bucket (versioned, encrypted, private) + DynamoDB lock table |

## Sizing decisions

| Decision | Choice | Why |
|---|---|---|
| Scylla instance | `r6i.xlarge` (4 vCPU / 32 GiB) | Memory-optimized, EBS-optimized. Budget: `r6i.large`. Reference-match: `r6i.2xlarge`. |
| Storage | EBS `gp3` via PVCs | **Online-resizable** — the requirement local-NVMe `i4i` (Scylla's own reference) cannot meet. |
| Node count | 3 → 5 | 3 = one per AZ (RF=3). Max 5 lets the cluster scale out under the same module. |
| Scaling | Cluster Autoscaler + managed node group max | You scale ScyllaDB by raising Operator `members`; pending pods trigger node scale-up. Never HPA for a stateful DB. |

## Remote state (do this first)

State lives in S3 with DynamoDB locking. The `bootstrap/` config creates that bucket + lock table with local state (the one thing that cannot live in remote state, since it must exist before the backend does).

```bash
cd bootstrap
terraform init
terraform apply -var state_bucket_name=chaithu-scylla-tfstate
cd ..
```

Then point the root module at that backend using partial config (backend blocks can't take variables, so values come from a file):

```bash
cp backend.hcl.example backend.hcl        # set your bucket/region
terraform init -backend-config=backend.hcl
```

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars
terraform apply
$(terraform output -raw update_kubeconfig_command)
```

Then install the in-cluster pieces (kept out of Terraform to keep a single clean apply):

```bash
kubectl apply -f ../k8s/storageclass.yaml       # gp3, allowVolumeExpansion: true

helm repo add autoscaler https://kubernetes.github.io/autoscaler && helm repo update
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --set autoDiscovery.clusterName=$(terraform output -raw cluster_name) \
  --set awsRegion=$(terraform output -raw region) \
  --set "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$(terraform output -raw cluster_autoscaler_role_arn)"
```

Annotate the ScyllaDB service account with the backup role so backups reach S3 with no static keys:

```bash
kubectl -n scylla annotate serviceaccount scylla-member \
  eks.amazonaws.com/role-arn=$(terraform output -raw scylla_s3_role_arn)
```

Schedule ScyllaDB pods onto the tainted node group by adding to each rack in `scylla-cluster.yaml`:

```yaml
placement:
  tolerations:
  - key: scylla.scylladb.com/dedicated
    operator: Equal
    value: "true"
    effect: NoSchedule
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: scylla.scylladb.com/node-pool
          operator: In
          values: ["scylla"]
```

## Scale 3 → 5

Edit `members` in the ScyllaCluster (Operator adds members); pending pods make Cluster Autoscaler grow the `scylla` node group up to `max 5`. No StatefulSet edits, no Terraform change.

## Grow a volume when the DB grows

The `gp3` StorageClass has `allowVolumeExpansion: true`, so expand online with no downtime:

```bash
kubectl -n scylla patch pvc <data-pvc> -p '{"spec":{"resources":{"requests":{"storage":"300Gi"}}}}'
```

gp3 volumes are increase-only and allow one size change per 6 hours; IOPS and throughput can be raised independently.

## Cost (approximate, us-east-1 on-demand — verify current pricing)

| Item | ~ / day |
|---|---|
| EKS control plane | $2.40 |
| 3× r6i.xlarge | $18 |
| 2× m6i.large | $4.60 |
| NAT + EBS | $2 |
| **Total** | **~$27/day** |

Run `terraform destroy` the moment the demo is done.
