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
| IRSA roles | EBS CSI and Cluster Autoscaler |
| S3 backup access | Bucket-scoped IAM policy attached to the Scylla node group instance role (keyless; agent uses the instance profile) |
| In-cluster runbook | `STEPS.md` — operator, cluster, data, resilience, scale, backup/restore |
| Remote state | `bootstrap/` creates an S3 state bucket (versioned, encrypted, private); locking via native S3 `use_lockfile` (Terraform ≥ 1.11) |

## Sizing decisions

| Decision | Choice | Why |
|---|---|---|
| Scylla instance | `r6i.xlarge` (4 vCPU / 32 GiB) | Memory-optimized, EBS-optimized. Budget: `r6i.large`. Reference-match: `r6i.2xlarge`. |
| Storage | EBS `gp3` via PVCs | **Online-resizable** — the requirement local-NVMe `i4i` (Scylla's own reference) cannot meet. |
| Node count | 3 → 5 | 3 = one per AZ (RF=3). Max 5 lets the cluster scale out under the same module. |
| Scaling | Cluster Autoscaler + managed node group max | You scale ScyllaDB by raising Operator `members`; pending pods trigger node scale-up. Never HPA for a stateful DB. |
