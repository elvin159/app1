# app1

Infrastructure and sample apps for **app1**: one AWS account per environment (dev, stg, prd), one
region in dev and two in stg and prd. Everything is applied by GitHub Actions. Nobody runs Terraform,
Docker or kubectl locally.

## Layout

```
app1/
├── apps/                      source, built once and promoted
│   ├── backend/               gunicorn API + Helm chart
│   ├── frontend/              gunicorn app (GET / → SELECT 1) + Helm chart + static/ for S3
│   └── argocd/                renders one Argo CD Application per app
├── dev/ stg/ prd/             one folder per AWS account
│   ├── global/                account level: ECR + replication, deploy roles, S3/CloudFront static site
│   └── us-east-1/ us-west-1/  region level, in this order:
│       ├── networking/        VPC, subnets, NAT                 terraform-aws-networking
│       ├── compute/           EKS cluster and nodes             terraform-aws-compute
│       ├── database/          RDS writer + read replica, or a cross-region replica   terraform-aws-database
│       ├── identity/          IRSA roles for the controllers    terraform-aws-identity
│       ├── platform/          ALB Controller, ExternalDNS, External Secrets, Cluster Autoscaler,
│       │                      Argo CD, ALB certificate, root Argo CD Application
│       ├── observability/     CloudWatch alarms                 terraform-aws-observability
│       ├── backend/values.yaml    version of each app running in this region
│       └── frontend/values.yaml
└── .github/workflows/         terraform, backend, frontend (+ reusable terraform-env, app)
```

Each folder with a `versions.tf` is a Terraform root with its own state. Roots find each other with
data sources (VPC by its `Name` tag, EKS cluster and RDS instances by name), never remote state.
In every root, only the `locals` block differs between environments and regions.

## Using a module

Every root calls one module from GitHub, pinned to a commit:

```hcl
module "database" {
  source = "git::https://github.com/elvin159/terraform-aws-database.git?ref=52027d8ee8910ef4388e4c98d39fd94b5f45d413"

  name       = local.cluster_name
  protection = local.protection
  # ...
}
```

To upgrade, change `ref` in every environment in one pull request and review the plans.

## Regions

The first region in each environment is the **primary**:

| | Primary (`us-east-1`) | Other regions (`us-west-1`) |
|---|---|---|
| Cluster | `app1-<env>-use1` | `app1-<env>-usw1` |
| Database | writer, `-read1` read replica, backups copied to `us-west-1` | cross-region read replica of the writer |
| Backend reads from | `-read1` | the local replica |
| Frontend `SELECT 1` on | the writer | the local replica |
| Images | pushed here | replicated by ECR |
| DB secret | here | read from the primary region |

Both regions serve the same hostnames (`backend.<env>.example.com`, `frontend.<env>.example.com`).
ExternalDNS creates one Route53 latency record per region, so users reach the closest healthy one.
The static site (`static.<env>.example.com`) is CloudFront, so it is global.

**Losing the primary region:** promote the `us-west-1` replica. In `<env>/us-west-1/database`, set
`primary_region = "us-west-1"` and `primary_cluster_name = "app1-<env>-usw1"` (do the same in
`identity`, `platform` and `observability` so they look up the new writer), and merge. The module
promotes the replica to a standalone writer with backups.

## How changes ship

| Change | Pull request | Merge to main |
|---|---|---|
| Terraform | `fmt`, `validate`, `plan` of every environment | `apply` dev → stg → prd, each after its environment's reviewers approve |
| `apps/backend`, `apps/frontend` | `pytest`, `helm lint` | build once → dev → promote to stg → promote to prd |

**Build once, promote:** an app's version is the Git SHA of the last commit that changed `apps/<app>`.

1. **dev:** the image is built and pushed to dev's ECR as `app1/<app>:<version>`. The version is
   committed to `dev/*/<app>/values.yaml`.
2. **stg** (after approval): the image is copied from dev's registry to stg's by digest, never
   rebuilt. The version is committed to `stg/*/<app>/values.yaml`.
3. **prd** (after approval): the same copy, from stg to prd.

Argo CD in each region sees the commit and deploys that version: the chart from that commit and the
image with that tag, so manifests and image move together. ECR replicates the image to the other
region. The frontend's static assets from the same commit are synced to the environment's bucket,
and CloudFront is invalidated.

The app pipelines also run after every successful `terraform apply`, so a new environment deploys
its apps without anyone pushing a change.

## Adding a region

1. Copy `<env>/us-west-1` to the new region folder. Change `region`, `cluster_name` and `vpc_cidr`
   (unique across every environment and region), and `az_count` if the region has fewer than three
   AZs.
2. Add the region to `replica_regions` in `<env>/global/main.tf` and to the environment's `regions`
   in `.github/workflows/terraform.yml`.
3. Replicate the Argo CD deploy key secret to the region.

## Prerequisites (account bootstrap)

These exist before this repo is used. The values in the code are stubs; replace them.

| What | dev | stg | prd |
|---|---|---|---|
| AWS account | `111111111111` | `222222222222` | `333333333333` |
| Terraform state bucket (us-east-1) | `app1-terraform-state-<account>` | | |
| Route53 zone | `dev.example.com` | `stg.example.com` | `prd.example.com` |
| Self-hosted runner label / egress IP | `app1-dev` / `203.0.113.10/32` | `app1-stg` / `.20` | `app1-prd` / `.30` |

In every account:

- GitHub OIDC provider `token.actions.githubusercontent.com`.
- `github-terraform-plan` (read-only plus state read, trusts `repo:elvin159/app1:pull_request`) and
  `github-terraform-apply` (trusts `repo:elvin159/app1:environment:<env>`).
- `platform-admin` role for people.
- Secrets Manager secret `app1/argocd-repo-ssh-key`: a read-only deploy key for this repo,
  replicated to every region.
- No other ECR replication configuration in the account; `global` owns it.

In GitHub:

- `dev`, `stg` and `prd` environments with required reviewers.
- Branch protection on `main` that requires a reviewed PR and lets `github-actions[bot]` push the
  version commits.
- Self-hosted runners have the AWS CLI. GitHub-hosted runners provide `yq` and `skopeo`.

## Operating Argo CD

Argo CD has no local admin user. With your EKS access (`platform-admin`), use `argocd --core` or
`kubectl -n argocd get applications`. To roll back an app in one environment, revert its version
commit; Argo CD syncs the previous version.
