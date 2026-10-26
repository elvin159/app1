#!/usr/bin/env bash
# Usage: sync-static.sh <directory>
# Uploads the frontend static assets to this account's bucket and invalidates CloudFront. The bucket
# and distribution come from SSM (global stack), not from this script.
set -euo pipefail
directory="$1"

bucket=$(aws ssm get-parameter --name /app1/static/bucket-name --query Parameter.Value --output text)
distribution=$(aws ssm get-parameter --name /app1/static/distribution-id --query Parameter.Value --output text)

aws s3 sync "$directory" "s3://$bucket" --delete
aws cloudfront create-invalidation --distribution-id "$distribution" --paths "/*"
