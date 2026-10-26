# stacks

All of app1's Terraform logic lives here, one module per layer. Each environment folder only holds
thin roots that call these modules, so a change made here applies to every environment and region.

## How a stack is called

Every root is a single `main.tf`, identical in every environment and region:

```
dev/us-east-1/database/main.tf    ──calls──▶   stacks/database
dev/global/main.tf                ──calls──▶   stacks/global
```

The root:

- takes the **environment** and **region** from its folder names (`<env>/<region>/<stack>`; the
  global root uses the environment's `primary_region`),
- reads `<env>/env.yaml` into `config`,
- configures the providers (AWS for every stack, Helm for `platform`),
- calls the stack with `region`, `config`, and `environment` where the stack needs it,
- re-exports the stack's outputs as one output named after the stack.

CI sets the state backend for each root: the bucket from `state_bucket` in `env.yaml`, and the key
`app1/<path under the environment>/terraform.tfstate`. See
[`.github/scripts/terraform.sh`](../.github/scripts/terraform.sh).

## The `config` contract

Each stack declares, in its `variables.tf`, only the `env.yaml` attributes it uses, with types.
Terraform drops the rest when it converts the decoded YAML, and fails the plan if an attribute is
missing or has the wrong type.

To add a setting:

1. Add it to every `env.yaml` (`dev`, `stg`, `prd`).
2. Add it to the stack's `config` type in `variables.tf`.
3. Use it as `var.config.<name>`, and add it to the stack's README.

## Order

Stacks run in this order, the primary region before the others. Each one finds what it needs from
earlier stacks with data sources, by name or tag. No stack reads another stack's state.

| # | Stack | Level | Creates | Needs from earlier stacks |
|---|---|---|---|---|
| 1 | [global](global/README.md) | account | ECR + replication, app deploy roles, S3/CloudFront static site | nothing |
| 2 | [networking](networking/README.md) | region | VPC, subnets, NAT gateways | nothing |
| 3 | [compute](compute/README.md) | region | EKS cluster, node group, access entries | VPC and private subnets |
| 4 | [database](database/README.md) | region | RDS writer + read replica, or a cross-region replica | VPC, subnets, cluster security group, the writer (other regions) |
| 5 | [identity](identity/README.md) | region | IRSA roles for the cluster controllers | cluster OIDC provider, the writer's secret |
| 6 | [platform](platform/README.md) | region | Controllers, Argo CD, ALB certificate, app wiring | cluster, IRSA roles, database instances |
| 7 | [observability](observability/README.md) | region | Alarm topic and CloudWatch alarms | database instances |

Names tie the lookups together: each region's VPC, cluster and database writer are all named after
the region's `cluster_name` in `env.yaml` (for example `app1-prd-use1`).

## Conventions

- **Module pins live only here.** Each stack calls one module from GitHub, pinned to a full commit
  SHA. To upgrade, change the `ref` in the stack's `main.tf` and review the plans of every
  environment in the pull request.
- **No provider blocks in stacks.** Roots own the providers. Resources that live in another region
  (database backup copies, ECR creation templates) use the resource's `region` argument.
- **Validated in CI.** `terraform fmt -check` covers `stacks/`; `terraform validate` runs on every
  root, which validates the stack it calls. See [`terraform.yml`](../.github/workflows/terraform.yml).
- **Update the README with the stack.** Each stack's README lists its `env.yaml` attributes and
  outputs; keep them in step with `variables.tf` and `outputs.tf`.
