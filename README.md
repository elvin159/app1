# app1

Infrastructure and sample apps for **app1**: one AWS account per environment (dev, stg, prd), one
region in dev and two in stg and prd. Everything is applied by GitHub Actions. Nobody runs Terraform,
Docker or kubectl locally.

## Layout

```
app1/
├── apps/                      source, built once and promoted
│   ├── backend/               gunicorn API
│   ├── frontend/              gunicorn app (GET / → SELECT 1) + static/ for S3
│   ├── chart/                 Helm chart shared by both apps
│   └── argocd/                renders one Argo CD Application per app
├── stacks/                    all Terraform logic, one module per stack
│   ├── global/                account level: ECR + replication, deploy roles, S3/CloudFront static site
│   ├── networking/            VPC, subnets, NAT                 → terraform-aws-networking
│   ├── compute/               EKS cluster and nodes             → terraform-aws-compute
│   ├── database/              writer + read replica, or a cross-region replica → terraform-aws-database
│   ├── identity/              IRSA roles for the controllers    → terraform-aws-identity
│   ├── platform/              ALB Controller, ExternalDNS, External Secrets, Cluster Autoscaler,
│   │                          Argo CD, ALB certificate, root Argo CD Application
│   └── observability/         CloudWatch alarms                 → terraform-aws-observability
├── dev/ stg/ prd/             one folder per AWS account
│   ├── env.yaml               everything that differs between environments
│   ├── global/main.tf         root: calls stacks/global
│   └── us-east-1/ us-west-1/  roots, applied in this order: networking, compute, database,
│       │                      identity, platform, observability (each a main.tf calling its stack)
│       ├── backend/values.yaml    version of each app running in this region
│       └── frontend/values.yaml
└── .github/                   workflows, the promote action, and scripts
```

Each folder with a `.terraform.lock.hcl` is a Terraform root with its own state. Roots are identical
in every environment and region: they take the environment and region from their folder names and
everything else from `env.yaml`, and call a module in `stacks/`. Stacks find each other with data
sources (VPC by its `Name` tag, EKS cluster and RDS instances by name), never remote state. CI sets
each root's state bucket (`state_bucket` in `env.yaml`) and key (`app1/<path>/terraform.tfstate`).

## Using a module

Each stack calls one module from GitHub, pinned to a commit, with values from `env.yaml`:

```hcl
# stacks/database/main.tf
module "database" {
  source = "git::https://github.com/elvin159/terraform-aws-database.git?ref=71fc1bb184a73a448a868cb899f7581605378dd5"

  name           = local.cluster_name
  protection     = var.config.protection
  instance_class = var.config.database.instance_class
  # ...
}
```

To upgrade a module, change its `ref` once in `stacks/` and review the plans of every environment.
To change an environment, edit its `env.yaml`.

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

**Losing the primary region:** set `primary_region: us-west-1` in `<env>/env.yaml` and merge. The
`us-west-1` database stack promotes its replica to a standalone writer with backups, and every other
stack follows the new primary.

## How changes ship

| Change | Pull request | Merge to main |
|---|---|---|
| Terraform | `fmt`, `validate`, `plan` of every environment | `apply` dev → stg → prd, each after its environment's reviewers approve |
| `apps/backend`, `apps/frontend` | `pytest`, `helm lint` | build once → dev → promote to stg → promote to prd |

**Build once, promote:** an app's version is the Git SHA of the last commit that changed `apps/<app>`
or the shared chart.

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

## Adding a region or an environment

- **Region:** add it under `regions` in `<env>/env.yaml` (cluster name, a VPC CIDR unique across
  every environment and region, AZ count), and copy any region folder of that environment to the new
  region's name. ECR replication, the database replica and the pipelines pick it up. Replicate the
  Argo CD deploy key secret to the region.
- **Environment:** copy an environment folder, edit its `env.yaml`, and add it to the plan matrix and
  apply chain in `.github/workflows/terraform.yml` and the promotion chain in `app.yml`.

## Prerequisites (account bootstrap)

These exist before this repo is used. The values are stubs in each `env.yaml`; replace them there.

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
- Self-hosted runners have the AWS CLI and `yq`. GitHub-hosted runners provide `yq` and `skopeo`.

## Going live

The code is complete and validated offline, but it has not been applied to AWS. What is left, in
order:

1. **Replace the stub values** in `dev/env.yaml`, `stg/env.yaml` and `prd/env.yaml`, under
   `# Bootstrap prerequisites`, with the real ones from the account bootstrap: `state_bucket`,
   `domain`, `hosted_zone_id`, `runner_egress_cidr`, `github_repo`, `deploy_subject`,
   `argocd_repo_ssh_secret`, `alarm_emails`. Also replace `account_id`, and the account IDs under
   `promotion`. Nothing else in the repo holds environment values. (The account IDs in
   `apps/chart/ci-values.yaml` and `apps/argocd/ci-values.yaml` only feed chart linting.)
2. **Publish the repo:** `git init` in `app1/`, push to `elvin159/app1`, and open a pull request to
   `main`. Check that the prerequisites above are in place first, especially the GitHub
   environments, branch protection and the self-hosted runners.
3. **Merge the first pull request.** Expect:
   - **terraform:** the PR plan stops at the first root that has never been applied (everything
     after it depends on it), so on a new account it plans `global` only. After merge, `apply` runs
     dev, then stg, then prd, each after its environment's reviewers approve.
   - **backend / frontend:** the run triggered by the merge itself fails at the AWS login, because
     the deploy roles and ECR don't exist until `global` is applied. The pipelines run again
     automatically after `terraform` succeeds and deploy dev. They then ask the `stg` and `prd`
     reviewers to approve the first promotion of each app.
4. **Optional: tag the database module.** Tag `v2.0.0` on `terraform-aws-database` commit
   `71fc1bb` and change the `ref` in `stacks/database/main.tf` to the tag. The commit pin works as
   it is.

Not verified before the first run: the Docker builds, the cross-account image copy (`skopeo`) and
`.github/scripts/set-version.sh`. They run for the first time in CI.

## Operating Argo CD

Argo CD has no local admin user. With your EKS access (`platform-admin`), use `argocd --core` or
`kubectl -n argocd get applications`. To roll back an app in one environment, revert its version
commit; Argo CD syncs the previous version.
