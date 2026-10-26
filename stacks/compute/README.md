# compute

The region's Kubernetes cluster: an EKS control plane, a managed node group, and the access entries
that decide who can use the Kubernetes API.

## Creates

Through [terraform-aws-compute](https://github.com/elvin159/terraform-aws-compute):

- An **EKS cluster** named `<cluster_name>` in the private subnets, with Kubernetes Secrets
  encrypted by a KMS key, control plane logs in CloudWatch Logs, an IAM OIDC provider for IRSA, and
  the core add-ons (CoreDNS, kube-proxy, VPC CNI) at the default versions for `kubernetes_version`.
- A **managed node group** `general`, scaled between `node_min_size` and `node_max_size`. Cluster
  Autoscaler (installed by [platform](../platform/README.md)) adds and removes nodes within those
  bounds; EKS tags the Auto Scaling group so Cluster Autoscaler can discover it.
- **Access entries** (the only principals with Kubernetes access; the identity that creates the
  cluster gets none):

  | Principal | Access | Why |
  |---|---|---|
  | `platform-admin` role | `AmazonEKSClusterAdminPolicy` | People operating the cluster. |
  | `github-terraform-apply` role | `AmazonEKSClusterAdminPolicy` | The platform stack's apply installs cluster-wide controllers. |
  | `github-terraform-plan` role | `AmazonEKSAdminViewPolicy` | The platform stack's plan reads Helm release state, which Helm stores in Secrets. Read-only, including Secrets. |

  The plan role's entry is declared directly in this stack, because the module only accepts the four
  common policies.

## Runs in

Every region, after networking. Root: `<env>/<region>/compute`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `account_id` | Builds the ARNs of the bootstrap roles in the access entries. |
| `regions.<region>.cluster_name` | Cluster name, and the `Name` tag used to find the VPC. |
| `protection` | `none` (dev): destroy works. `standard` (stg): EKS deletion protection. `strict` (prd): also fails any plan that would destroy or replace the cluster. |
| `runner_egress_cidr` | The only CIDR allowed to the public Kubernetes API endpoint: the self-hosted runner. |
| `compute.kubernetes_version` | Kubernetes minor version, e.g. `"1.35"`. |
| `compute.node_instance_types` | Instance types for the node group, all the same size. |
| `compute.node_capacity_type` | `SPOT` (dev) or `ON_DEMAND`. |
| `compute.node_min_size` / `compute.node_max_size` | Autoscaling bounds for the node group. |
| `log_retention_days` | Days to keep control plane logs. |
| `kms_key_deletion_window_days` | Waiting period before the Secrets KMS key is deleted after a destroy. |

## Looks up

| What | How |
|---|---|
| VPC | `aws_vpc` with tag `Name = <cluster_name>` (networking). |
| Private subnets | `aws_subnets` in that VPC with tag `kubernetes.io/role/internal-elb = 1`. |

## Outputs

| Output | Value |
|---|---|
| `cluster_name` | EKS cluster name. |
| `cluster_endpoint` | Kubernetes API endpoint. |
| `cluster_security_group_id` | Security group EKS created for the control plane and nodes; database allows it. |
| `oidc_provider_arn` | IAM OIDC provider ARN, for IRSA roles. |

## Module

[terraform-aws-compute](https://github.com/elvin159/terraform-aws-compute) at
`18476b736bf8ba8ac44aac0c2036e69052cf8e7a`.

## Operating notes

- **API access.** The private endpoint is always on; nodes use it. The public endpoint is open only
  to `runner_egress_cidr`, because the platform stack runs Helm from the self-hosted runner. App
  deployments never need the API from CI: Argo CD runs inside the cluster.
- **Upgrading Kubernetes.** Raise `compute.kubernetes_version` one minor version at a time, in dev
  first. Update the Cluster Autoscaler chart in platform to the release for that version at the same
  time.
- **Destroying stg or prd.** Lower `protection` to `none` in that `env.yaml` and apply first. With
  `strict`, Terraform refuses the plan by design.
