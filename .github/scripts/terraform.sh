#!/usr/bin/env bash
# Usage: terraform.sh <environment> <plan|apply>
# Runs every root of an environment in dependency order: global, then each region's stacks, the
# primary region first because the other regions replicate its database. Settings come from
# <environment>/env.yaml; each root's state key is its path.
set -euo pipefail
environment="$1" command="$2"
config="$environment/env.yaml"
primary=$(yq '.primary_region' "$config")
others=$(yq '.regions | keys | .[]' "$config" | grep -vx "$primary" || true)
bucket=$(yq '.state_bucket' "$config")

roots="global"
for region in $primary $others; do
  for stack in networking compute database identity platform observability; do
    roots="$roots $region/$stack"
  done
done

for root in $roots; do
  dir="$environment/$root"
  echo "::group::$dir"
  terraform -chdir="$dir" init -backend-config="bucket=$bucket" -backend-config="key=app1/$root/terraform.tfstate"

  if [ "$command" = apply ]; then
    terraform -chdir="$dir" plan -out=tfplan
    terraform -chdir="$dir" apply tfplan
    echo "::endgroup::"
    continue
  fi

  # Read-only role: no state lock. Plans never write state.
  terraform -chdir="$dir" plan -lock=false -no-color | tee "$RUNNER_TEMP/plan.txt"
  echo "::endgroup::"
  {
    echo "<details><summary><code>$dir</code></summary>"
    echo
    echo '```'
    cat "$RUNNER_TEMP/plan.txt"
    echo '```'
    echo "</details>"
  } >> "$GITHUB_STEP_SUMMARY"
  # Later roots look this one up, so they can't be planned until it has been applied.
  if [ -z "$(terraform -chdir="$dir" state list)" ]; then
    echo "::notice::$dir has not been applied yet; the roots after it are planned once it is."
    break
  fi
done
