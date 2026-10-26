# identity

IAM roles for the controllers that run in the region's cluster. Each role is assumed by one
Kubernetes service account through IRSA, so no controller holds AWS credentials.

## Creates

Through [terraform-aws-identity](https://github.com/elvin159/terraform-aws-identity), one IRSA role
per controller, named `<cluster_name>-<controller>`:

| Role | Service account | Allows |
|---|---|---|
| `<cluster_name>-cluster-autoscaler` | `kube-system/cluster-autoscaler` | Scale only the Auto Scaling groups tagged for this cluster. |
| `<cluster_name>-aws-load-balancer-controller` | `kube-system/aws-load-balancer-controller` | Manage ALBs, target groups and their security groups. |
| `<cluster_name>-external-dns` | `kube-system/external-dns` | Change records in `hosted_zone_id` only. |
| `<cluster_name>-external-secrets` | `external-secrets/external-secrets` | Read the database master secret (and decrypt it with its KMS key) and the Argo CD deploy key. Nothing else in Secrets Manager. |

## Runs in

Every region, after database. It needs the cluster's OIDC provider (compute) and the writer's
secret (database). Root: `<env>/<region>/identity`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `regions.<region>.cluster_name` | Role name prefix, and the cluster to trust. |
| `primary_region` | Where the writer, and so the master secret, lives. |
| `hosted_zone_id` | The only Route53 zone ExternalDNS may change. |
| `argocd_repo_ssh_secret` | Name of the Secrets Manager secret holding Argo CD's read-only deploy key, replicated to every region. |

## Looks up

| What | How |
|---|---|
| Cluster and its OIDC provider | `aws_eks_cluster` named `<cluster_name>`, then `aws_iam_openid_connect_provider` by its issuer URL (compute). |
| Master secret and its KMS key | `aws_db_instance` named after the primary region's `cluster_name`, in `primary_region` (database). |
| Argo CD deploy key | `aws_secretsmanager_secret` named `argocd_repo_ssh_secret`, in this region (bootstrap). |

## Outputs

| Output | Value |
|---|---|
| `cluster_autoscaler_role_arn` | Cluster Autoscaler role ARN. |
| `aws_load_balancer_controller_role_arn` | AWS Load Balancer Controller role ARN. |
| `external_dns_role_arn` | ExternalDNS role ARN. |
| `external_secrets_role_arn` | External Secrets Operator role ARN. |

## Module

[terraform-aws-identity](https://github.com/elvin159/terraform-aws-identity) at
`45396f363d586d257e60a4499cec1b1822c34c12`.

## Operating notes

- **Names are the contract.** [platform](../platform/README.md) finds each role by
  `<cluster_name>-<controller>` and annotates the matching service account with it. The service
  account names above must match the Helm values in platform.
- **Other regions read the secret from the primary region.** The External Secrets role is granted
  the writer's secret ARN and KMS key in `primary_region`, because a replica has no secret of its
  own.
- **Least privilege for the app.** The apps connect with the RDS master user. For production, create
  a dedicated database role and give External Secrets only that secret.
