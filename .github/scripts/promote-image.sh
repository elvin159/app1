#!/usr/bin/env bash
# Usage: promote-image.sh <app> <version> <source account> <target account>
# Copies an image from the previous environment's registry, keeping its digest: the bytes that ran in
# the previous environment are the bytes that run here. Needs credentials for the target account's
# deploy role, which the source registry lets pull.
set -euo pipefail
app="$1" version="$2" source_account="$3" target_account="$4"
region="${AWS_REGION:?}"
repository="app1/$app"

if aws ecr describe-images --repository-name "$repository" --image-ids imageTag="$version" > /dev/null 2>&1; then
  echo "$repository:$version is already in $target_account"
  exit 0
fi

# One ECR token works for every registry the role can access.
token=$(aws ecr get-login-password)
skopeo copy --all --preserve-digests \
  --src-creds "AWS:$token" --dest-creds "AWS:$token" \
  "docker://$source_account.dkr.ecr.$region.amazonaws.com/$repository:$version" \
  "docker://$target_account.dkr.ecr.$region.amazonaws.com/$repository:$version"
