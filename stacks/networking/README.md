# networking

The region's network: a VPC with public and private subnets across Availability Zones, and NAT
gateways for outbound traffic from the private subnets.

## Creates

Through [terraform-aws-networking](https://github.com/elvin159/terraform-aws-networking):

- A VPC with the region's `vpc_cidr`, tagged `Name = <cluster_name>`.
- One public and one private subnet per Availability Zone, tagged for load balancers
  (`kubernetes.io/role/elb` on public, `kubernetes.io/role/internal-elb` on private).
- NAT gateways (one per AZ, or one in total when `single_nat_gateway` is on) and route tables.
- VPC flow logs to CloudWatch Logs.

## Runs in

Every region, first. Root: `<env>/<region>/networking`.

## Reads from `env.yaml`

| Attribute | Controls |
|---|---|
| `regions.<region>.cluster_name` | The VPC's `Name` tag and the prefix of every resource name. |
| `regions.<region>.vpc_cidr` | The VPC CIDR, an RFC1918 `/16`. Must be unique across every environment and region, so VPCs can be connected later. |
| `regions.<region>.az_count` | Number of AZs: 3, or 2 in regions that have only two (us-west-1). |
| `networking.single_nat_gateway` | One NAT gateway instead of one per AZ. Cheaper, but not highly available: dev only. |
| `log_retention_days` | Days to keep VPC flow logs. |

## Looks up

Nothing. This is the first regional stack.

## Outputs

| Output | Value |
|---|---|
| `vpc_id` | VPC ID. |
| `private_subnet_ids` | Private subnet IDs, one per AZ. |
| `nat_public_ips` | NAT gateway public IPs: outbound traffic from the cluster comes from these, for allow-listing. |

## Module

[terraform-aws-networking](https://github.com/elvin159/terraform-aws-networking) at
`b929e585ecde926a9164b161091dc9abb465f278`.

## Operating notes

- **The `Name` tag is the contract.** compute and database find the VPC by `Name = <cluster_name>`
  and the private subnets by the `kubernetes.io/role/internal-elb` tag. Renaming `cluster_name`
  replaces the network and breaks those lookups until every stack is re-applied.
- **Changing `vpc_cidr` or `az_count` replaces the VPC** and everything in it. Choose them before the
  first apply.
