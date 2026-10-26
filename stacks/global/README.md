# global

Account-level resources for app1: the container registry, the roles the app pipelines deploy with,
and the frontend's static site. Anything that is global in AWS, or named in IAM, lives here so a
second region never collides with the first.

## Creates

- **ECR repositories** `app1/backend` and `app1/frontend` in the primary region: immutable tags, scan
  on push, and a lifecycle policy that keeps the last 50 images.
- **ECR replication** of `app1/*` to every other region in `env.yaml`, plus a repository creation
  template in each of those regions so replicated repositories get the same settings (immutable
  tags, lifecycle policy, AES256 encryption). Skipped when the environment has one region.
- **Promotion pull access**: a repository policy that lets the next environment's deploy role pull
  images (dev → stg → prd). The policy uses an ARN condition, so the role doesn't have to exist yet.
- **Deploy roles** `github-app1-backend` and `github-app1-frontend`, assumed by GitHub Actions through
  the account's OIDC provider. They trust only `deploy_subject`. Each can push and pull its own
  repository and, outside dev, pull the same repository from the previous environment.
- **Static site**: an S3 bucket behind CloudFront on `static.<domain>`, with an ACM certificate,
  through [terraform-aws-bucket](https://github.com/elvin159/terraform-aws-bucket). The frontend role
  may sync the bucket and invalidate the distribution.
- **SSM parameters** `/app1/static/bucket-name` and `/app1/static/distribution-id`, read by the
  frontend pipeline instead of hardcoding names.

## Runs in

The account, once per environment, before any region. The root is `<env>/global`; it deploys to the
environment's `primary_region`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `account_id` | Registry ID for replication; the provider's allowed account. |
| `primary_region` | Where the repositories and SSM parameters are created. |
| `regions` | Every key other than `primary_region` becomes a replication destination. |
| `force_destroy` | Whether repositories and the bucket can be destroyed with content in them. `true` in dev only. |
| `promotion.source_account_id` | The previous environment, whose repositories the deploy roles may pull from. `null` in dev. |
| `promotion.target_account_id` | The next environment, whose deploy roles may pull from here. `null` in prd. |
| `domain` | The static site is served on `static.<domain>`. |
| `hosted_zone_id` | Route53 zone for the static site's record and certificate validation. |
| `deploy_subject` | The only GitHub OIDC subject the deploy roles trust, for example `repo:elvin159/app1:environment:prd`. |

The root also passes `environment` (from the folder name), used in the bucket name
`app1-<env>-static-<account_id>`.

## Looks up

The account's GitHub OIDC provider, `token.actions.githubusercontent.com`, created during account
bootstrap.

## Outputs

| Output | Value |
|---|---|
| `ecr_repository_urls` | Repository URL per app, in the primary region. Replica regions use the same path. |
| `github_deploy_role_arns` | Deploy role ARN per app. |
| `static_bucket_name` | S3 bucket for the frontend static assets. |
| `static_distribution_id` | CloudFront distribution ID. |
| `static_urls` | Static site URLs. |

## Module

[terraform-aws-bucket](https://github.com/elvin159/terraform-aws-bucket) at
`0d9d63ed5102dd424664ca0cc19d5a3ead310c92`. The rest is declared in this stack.

## Operating notes

- **One replication configuration per registry.** ECR allows a single replication configuration per
  account and region, and this stack owns it. Don't configure ECR replication for anything else in
  the same account, or the two will overwrite each other.
- **Images are pushed once.** The pipelines push only to the primary region. Replication copies the
  image to the other regions, usually within minutes.
- **Promotion.** The `promote` action copies an image from the previous environment's registry by
  digest, using this environment's deploy role. See [How changes ship](../../README.md#how-changes-ship).
- **Changing `deploy_subject`** changes which workflows can deploy. dev trusts pushes to `main`;
  stg and prd trust only jobs running in their GitHub Environment, which require approval.
