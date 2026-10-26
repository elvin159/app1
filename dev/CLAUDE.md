# Decisions

These override anything below that contradicts them. The repo's `README.md` (at `app1/`) is the operator guide.

1. **Scope:** app1 is onboarded onto new EKS clusters in AWS accounts that are **already bootstrapped** (one account per environment). Account bootstrap is out of scope; see Prerequisites in the README. Everything runs through CI/CD with zero manual steps.
2. **Layout:** `apps/` holds the source (built once) and the shared `apps/chart`. `stacks/` holds all Terraform logic, one module per stack. `dev/`, `stg/` and `prd/` each have an `env.yaml` (every value that differs between environments, read by Terraform and the workflows), `global/`, and one folder per region (dev: `us-east-1`; stg and prd: `us-east-1` primary + `us-west-1`). Roots are thin and identical everywhere: environment and region come from the folder names.
3. **Order:** `global → <primary region>/{networking → compute → database → identity → platform → observability} → <other regions>/{same}`. identity needs compute's OIDC provider and the writer's secret; other regions replicate the primary's database.
4. **Account level (`global/`):** ECR repos `app1/<app>` in the primary region, with ECR replication to the other regions; GitHub deploy roles `github-app1-<app>`; the S3/CloudFront static site (`static.<env>.example.com`) and its SSM parameters. Anything IAM-named or global lives here, never per region.
5. **Region level:** VPC, EKS (`app1-<env>-<use1|usw1>`), RDS, IRSA roles, controllers + Argo CD, ALB certificate, alarms. Names carry the region code so IAM names never collide across regions.
6. **Database:** `terraform-aws-database` (commit `71fc1bb` on main) supports in-region read replicas, cross-region read replicas and cross-region backup copies. Primary region: writer + `read1` replica + backups copied to `us-west-1` (stg/prd). Other regions: a cross-region replica of the writer. The **backend reads from a replica** (`read1`, or the local cross-region replica). The frontend's `SELECT 1` uses the writer where local, else the local replica. The master secret stays in the primary region; External Secrets reads it from there.
7. **Build once, promote:** an app's version is the Git SHA of the last commit to `apps/<app>`. It is both the image tag and the chart revision. Merge to main builds the image once into dev's ECR and deploys dev. Promotion to stg then prd copies the same image by digest (skopeo) from the previous environment's registry, behind the `stg`/`prd` GitHub Environment approvals. Deploying = committing the version to `<env>/<region>/<app>/values.yaml`; Argo CD syncs it.
8. **Argo CD:** installed by Terraform (`platform`). A root Application (app-of-apps) renders `apps/argocd`, which creates one Application per app pinned to the region's version. Terraform passes the infrastructure values (ECR URL, DB hosts, secret, hostnames).
9. **DNS:** both regions serve the same hostnames; ExternalDNS creates Route53 latency records with one set identifier per region.
10. **Frontend is pod only:** gunicorn behind the ALB, `GET /` runs `SELECT 1;` and returns JSON. `apps/frontend/static/` (environment-agnostic) is synced to S3/CloudFront by the pipeline, which also invalidates the cache.
11. **EKS API access from CI:** public endpoint restricted to the bootstrapped runner's egress IP; only the `platform` stack needs it. App deploys never touch the cluster.
12. **Pinning:** modules by commit SHA; Terraform `1.17.0`, AWS `6.70.0`, Helm `3.3.0`, every chart, Action and Python package pinned; lock files committed.
13. **Wiring and DRY:** data sources by name or tag; no `terraform_remote_state`. Each value lives in one place: environment values in `env.yaml`, logic in `stacks/`, module pins in `stacks/`, the state backend set by CI from `env.yaml` and the root's path.
14. **Auth and approvals:** OIDC only. Plan uses the read-only `github-terraform-plan` role (PRs); apply uses `github-terraform-apply` (`environment:<env>`). Branch protection requires a reviewed PR; `dev`/`stg`/`prd` environments gate applies and promotions.
15. **Documentation:** every stack has a README (what it creates, `env.yaml` attributes, lookups, outputs, operating notes), indexed by `stacks/README.md` and linked from the root README. Update a stack's README in the same change as the stack.

# About

Each environment folder (`dev/`, `stg/`, `prd/`) holds the Terraform that builds that environment's account-level (`global/`) and per-region infrastructure, named by the folder names. It must be production quality. Assume multiple AWS accounts: one each for development, staging and production. Follow the keep it simple stupid (KISS) principle of system administration. Terraform code must be clean and versions must be pinned. Use OIDC, and DO NOT rely on AWS secrets.

Each folder inside a region uses the module with the matching name in `../../` (`terraform-aws-<folder>`), sourced from GitHub (see Decisions 12). `global/` uses `terraform-aws-bucket` for the static site.

Stacks run in the order given in Decisions 3. The infrastructure must be in place before the frontend and backend are deployed.

Modules wire into each other using outputs, and across stacks through data sources (Decisions 13).

# frontend

Deployed with a Helm chart (pod only, see Decisions 10). Source: `apps/frontend`.

- `GET /` executes `SELECT 1;` on RDS and returns JSON.
- Use gunicorn and simple Python code. Keep the HTML very simple.
- The simple HTML page (`static/`) goes to the S3 bucket provisioned by the `global` stack and is served through CloudFront.

Frontend pipeline: run tests, build the image once (Git SHA tag), push to ECR, sync web assets to S3, invalidate the CloudFront cache, update the Git manifests; then promote the same image and assets to stg and prd (Decisions 7).

# backend

Deployed with a Helm chart. Use gunicorn and simple Python code, with an AlmaLinux base image if needed. Source: `apps/backend`. Reads from a read replica (Decisions 6).

replicas > 1 (minimum 2 replicas).

Backend pipeline: build the Docker container once (Git SHA tag), push to ECR, auto-update the Git manifests; then promote the same image to stg and prd (Decisions 7).

Sample backend output. None of these values may be hardcoded: `pod_name` comes from the Downward API, `db_status` from a real connection attempt, and `timestamp` is the current UTC time.

```
{
"pod_name": "backend-api-79b88448f4-x8z2k",
"db_status": "connected",
"timestamp": "2026-10-12T09:44:00Z"
}
```

# CI/CD

Key focus: 100% CI/CD automation.
Both the GitHub Actions workflows that provision the infrastructure (Terraform) and those that run the application deployments will be thoroughly reviewed. The whole process must be 100% automated through CI/CD: nothing may rely on manual steps or local CLI runs. Account bootstrap is assumed complete (Prerequisites in the README) and is not part of this repo.

# argocd

Configured to sync application state from Git automatically (automated sync, prune, selfHeal). Argo CD is installed into the cluster by Terraform in the `platform` stack.

# external secrets operator

Fetches credentials from AWS Secrets Manager and maps them into Kubernetes Secrets.

# AWS ALB Controller

Provisions AWS Application Load Balancers automatically from Kubernetes Ingress resources.

# ExternalDNS

Syncs Route53 DNS records dynamically from Ingress hostnames.

# Function

This repo sets up the infrastructure for an application using the modules terraform-aws-networking, terraform-aws-compute, terraform-aws-database, terraform-aws-identity, terraform-aws-bucket and terraform-aws-observability.

It makes sure the right infrastructure is in place for each configured environment and region.

Once the EKS cluster is running with the required controllers, Argo CD deploys the sample frontend and backend Helm charts, which use that infrastructure. PLAN before writing any code.

# README.md

Keep it simple: explain how to source the modules and use them for different environments and regions. It lives at the repo root (`app1/README.md`).

# github actions

Keep the workflows simple. Use separate jobs for terraform fmt, validate and plan. Planning authenticates with OIDC. terraform plan runs only when a PR to main is opened or new commits are pushed to its branch. terraform apply runs only when the PR merges with the required approvals.

When the frontend or backend changes in Git, run tests for the language used (pytest). Once tests pass, the pipeline builds once, commits the version to Git for dev, and promotes it to stg and prd after approval; Argo CD syncs each change to the Kubernetes clusters. terraform apply runs dev, then stg, then prd, each after approval.
