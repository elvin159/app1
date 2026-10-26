#!/usr/bin/env bash
# Usage: set-version.sh <environment> <app> <version>
# Points every region of an environment at one version of an app and pushes the change to main.
# Argo CD sees the commit and syncs each region's cluster.
set -euo pipefail
environment="$1" app="$2" version="$3"

files=("$environment"/*/"$app"/values.yaml)
changed=false
for f in "${files[@]}"; do
  if [ "$(yq ".$app.version" "$f")" != "$version" ]; then
    yq -i ".$app.version = \"$version\"" "$f"
    changed=true
  fi
done

if [ "$changed" = false ]; then
  echo "$environment already runs $app $version"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "$app: deploy $version to $environment" -- "${files[@]}"

# Commits pushed with GITHUB_TOKEN don't trigger workflows, so this doesn't loop. Other pipelines
# push to main too, so rebase and retry on a race.
for attempt in 1 2 3; do
  if git pull --rebase origin main && git push origin HEAD:main; then
    exit 0
  fi
  echo "push attempt $attempt failed, retrying"
  sleep $((attempt * 5))
done
exit 1
