# observability

Alarms for the region's database, emailed through an encrypted SNS topic.

## Creates

Through [terraform-aws-observability](https://github.com/elvin159/terraform-aws-observability):

- An **SNS topic** `<cluster_name>-alarms`, encrypted with a KMS key, with an email subscription per
  address in `alarm_emails`. Notifications are sent when an alarm fires and when it recovers.
- **CloudWatch alarms**, named `<cluster_name>-<key>`, for each database instance in the region:

  | Alarm key | Instances | Fires when |
  |---|---|---|
  | `rds-<role>-cpu-high` | every instance | CPU above 80% for 15 minutes. |
  | `rds-<role>-storage-low` | every instance | Free storage below 2 GiB. |
  | `rds-<role>-replica-lag` | replicas only | More than 60 seconds behind the writer for 15 minutes. |

  `<role>` is `writer` and `read1` in the primary region, and `replica` in other regions.

## Runs in

Every region, last. Root: `<env>/<region>/observability`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `regions.<region>.cluster_name` | Topic and alarm names, and the database identifiers to watch. |
| `primary_region` | Which instances exist here: writer and `read1`, or a cross-region replica. |
| `alarm_emails` | Email addresses subscribed to the topic. |

## Looks up

Nothing. It watches the database instances by identifier (`<cluster_name>`,
`<cluster_name>-read1`), which the database stack creates.

## Outputs

| Output | Value |
|---|---|
| `sns_topic_arn` | Alarm topic ARN, for alarms created elsewhere. |
| `alarm_names` | Alarm names, by key. |

## Module

[terraform-aws-observability](https://github.com/elvin159/terraform-aws-observability) at
`1b3d393b9ca3d0bec48bf5fd69c53dc3e5c7399f`.

## Operating notes

- **Confirm the subscription.** Each address in `alarm_emails` gets a confirmation email from AWS
  and receives nothing until the link is clicked.
- **Adding an alarm.** Add an entry to the `alarms` map in [`main.tf`](main.tf); the key becomes part
  of the alarm name. Alarms can only notify a topic in their own region, which is why this stack runs
  per region.
