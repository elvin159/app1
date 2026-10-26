# database

The region's PostgreSQL database. In the primary region it is the writer, a read replica and
cross-region backup copies; in every other region it is a cross-region read replica of the writer.

## Creates

Through [terraform-aws-database](https://github.com/elvin159/terraform-aws-database), PostgreSQL 17,
private, SSL enforced, encrypted with a KMS key in the region:

| | Primary region | Other regions |
|---|---|---|
| Instance `<cluster_name>` | The writer, database `app1`. RDS generates the master password, keeps it in Secrets Manager and rotates it. | A cross-region read replica of the writer. Same databases and users; no secret or automated backups of its own. |
| `<cluster_name>-read1` | In-region read replica. The backend reads from it. | — |
| Backup copies | The writer's automated backups are copied to the environment's next region (stg/prd: us-west-1), with a KMS key there. | — |
| Security group | Postgres (5432) from the region's EKS cluster security group only. | Same. |

## Runs in

Every region, after compute. The primary region must be applied before the others, because their
replicas need the writer. Root: `<env>/<region>/database`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `regions.<region>.cluster_name` | Instance identifier, and the name used to find the VPC and cluster. |
| `primary_region` | Whether this region holds the writer, and where other regions find it. |
| `regions` | The first region other than `primary_region` receives the backup copies. |
| `protection` | `none` (dev): destroy works, no final snapshot. `standard` (stg): deletion protection and a final snapshot. `strict` (prd): also fails any plan that would destroy or replace the instance. |
| `database.instance_class` | Instance class for the writer and replicas. |
| `database.multi_az` | Standby in a second AZ with automatic failover, for every instance. Off in dev only. |
| `database.allocated_storage` / `database.max_allocated_storage` | Initial gp3 storage and the autoscaling ceiling, in GiB. |
| `database.backup_retention_days` | Days of point-in-time recovery on the writer, and days the cross-region copies are kept. |
| `database.apply_immediately` | Apply changes now instead of in the maintenance window. dev only. |
| `log_retention_days` | Days to keep PostgreSQL logs. |
| `kms_key_deletion_window_days` | Waiting period before the KMS keys are deleted after a destroy. |

## Looks up

| What | How |
|---|---|
| VPC and private subnets | By `Name = <cluster_name>` and the `kubernetes.io/role/internal-elb` tag (networking). |
| Cluster security group | `aws_eks_cluster` named `<cluster_name>` (compute). |
| The writer (other regions only) | `aws_db_instance` named after the primary region's `cluster_name`, in `primary_region`. |

## Outputs

| Output | Value |
|---|---|
| `identifier` | The writer's identifier in the primary region; the replica's elsewhere. |
| `address` | Hostname of this region's instance. |
| `read_replica_addresses` | Hostnames of the in-region read replicas (primary region only). |
| `master_user_secret_arn` | The master credentials secret (primary region only; replicas use the writer's). |

## Module

[terraform-aws-database](https://github.com/elvin159/terraform-aws-database) at
`71fc1bb184a73a448a868cb899f7581605378dd5`.

## Operating notes

- **Who connects where** is decided in [platform](../platform/README.md): the backend reads from
  `-read1` (or this region's replica), the frontend's `SELECT 1` uses the writer where it is local.
- **Credentials.** The master secret stays in the primary region. External Secrets in every region
  reads it from there (see [identity](../identity/README.md)) and keeps the last copy if that region
  is unreachable.
- **Losing the primary region: not automated yet.** The module promotes a replica to a standalone
  writer when it is no longer given `replicate_source_db`, and promotion is one-way. In this stack
  that happens when `primary_region` changes. But `primary_region` also decides where the global
  stack deploys and where backups are copied, so changing it during an outage would also try to move
  ECR and the static site and copy backups to the lost region. A tested failover procedure (a
  separate setting for the writer's region) is an open follow-up. Until then, the cross-region
  replica and the backup copies preserve the data, but failover needs an engineered change.
- **Replication lag.** Replicas are asynchronous; [observability](../observability/README.md) alarms
  when a replica is more than 60 seconds behind.
- **Major upgrades** are not automatic: the engine version is pinned to 17 in this stack.
