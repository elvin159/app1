# platform

Everything that runs inside the region's cluster before the apps: the controllers, Argo CD, the
certificate for the apps' load balancer, and the wiring that tells Argo CD what to deploy and how
the apps reach their database.

## Creates

**Helm releases** (chart versions pinned in [`helm.tf`](helm.tf)):

| Release | Chart | Version | Namespace | Does |
|---|---|---|---|---|
| `aws-load-balancer-controller` | `aws-load-balancer-controller` | 3.5.0 | `kube-system` | Creates an ALB for the apps' Ingresses (one shared ALB, `group.name: app1`). |
| `external-dns` | `external-dns` | 1.23.0 | `kube-system` | Creates Route53 records for Ingress hostnames, in `domain` only. |
| `external-secrets` | `external-secrets` | 2.12.0 | `external-secrets` | Copies Secrets Manager secrets into Kubernetes Secrets. |
| `cluster-autoscaler` | `cluster-autoscaler` | 9.59.0 | `kube-system` | Adds and removes nodes within the node group's bounds (compute). |
| `argocd` | `argo-cd` | 10.10.3 | `argocd` | Syncs the apps from Git. Dex and the local admin user are off. |
| `platform-config` | local, [`charts/platform-config`](charts/platform-config) | — | `argocd` | See below. Installed last, after the other charts' CRDs exist. |

Each controller's service account is annotated with its IRSA role from
[identity](../identity/README.md).

**`platform-config`** (a local chart, so its custom resources are applied after the CRDs):

- A `ClusterSecretStore` per region it needs, `aws-secrets-manager-<region>`: this region (for the
  deploy key) and the primary region (for the database master secret).
- An `ExternalSecret` that builds Argo CD's repository credentials from the deploy key.
- The root Argo CD Application `app1` (app-of-apps). It renders [`apps/argocd`](../../apps/argocd),
  which creates one Application per app pinned to the version in
  `<env>/<region>/<app>/values.yaml`, using the shared chart [`apps/chart`](../../apps/chart).

The values passed to each app:

| Value | backend | frontend |
|---|---|---|
| Workload name | `backend-api` | `frontend` |
| Replicas | `apps.replicas` | `apps.replicas` |
| Image | `<account>.dkr.ecr.<region>.amazonaws.com/app1/backend` (this region's replica) | `.../app1/frontend` |
| Hostname | `backend.<domain>` | `frontend.<domain>` |
| Database host | `<cluster_name>-read1` in the primary region; this region's replica elsewhere | the writer in the primary region; this region's replica elsewhere |
| Database secret | the writer's master secret, through `aws-secrets-manager-<primary_region>` | same |
| DNS | latency record with set identifier `<region>` | same |

**ACM certificate** `*.<domain>` in this region, validated through Route53. The ALB controller picks
it by the Ingress hostname.

## Runs in

Every region, after identity. Root: `<env>/<region>/platform`. It is the only stack that talks to
the Kubernetes API: the root configures the Helm provider with a token from the CI role's AWS
session (`aws eks get-token`).

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `account_id` | ECR registry in image URLs. |
| `regions.<region>.cluster_name` | Cluster to install into, IRSA role names, database identifiers. |
| `primary_region` | Where the writer and its secret are, and which secret store the apps use. |
| `apps.replicas` | Replicas per app. The chart refuses fewer than 2. |
| `domain` | App hostnames, the certificate, and ExternalDNS's domain filter. |
| `hosted_zone_id` | Zone for certificate validation records. |
| `github_repo` | Repository Argo CD pulls (`git@github.com:<github_repo>.git`). |
| `argocd_repo_ssh_secret` | Secrets Manager secret with Argo CD's deploy key. |

The root also passes `environment`, used to point Argo CD at `<env>/<region>/<app>/values.yaml`.

## Looks up

| What | How |
|---|---|
| Cluster | `aws_eks_cluster` named `<cluster_name>` (compute), also used by the root's Helm provider. |
| IRSA roles | `aws_iam_role` named `<cluster_name>-<controller>` (identity). |
| Writer | `aws_db_instance` named after the primary region's `cluster_name`, in `primary_region` (database): database name and master secret. |
| Each app's database instance | `aws_db_instance` in this region, as in the table above (database). |

## Outputs

| Output | Value |
|---|---|
| `app_urls` | App URLs. Every region serves the same hostnames. |
| `app_database_hosts` | Database host each app connects to in this region. |

## Module

None: this stack declares its resources directly.

## Operating notes

- **EKS API access.** Plans and applies of this stack run on the self-hosted runner, the only
  address allowed to the cluster's public endpoint (see [compute](../compute/README.md)).
- **Argo CD has no local admin.** Use `argocd --core` or `kubectl -n argocd get applications` with
  `platform-admin` access. Applications sync automatically (prune and self-heal).
- **Upgrading a controller.** Change its chart `version` in `helm.tf`, check the chart's upgrade
  notes, and review the plan in every environment. Keep Cluster Autoscaler on the release that
  matches `compute.kubernetes_version`.
- **Same hostnames in every region.** Each region's ExternalDNS writes its own latency record (set
  identifier = region), so Route53 sends users to the closest region.
