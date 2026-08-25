#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-scylla}"
CLUSTER="${CLUSTER:-scylladb}"
EXPECTED="${1:-3}"

POD="$(kubectl -n "$NS" get pods -l scylla/cluster="$CLUSTER" \
  -o jsonpath='{.items[0].metadata.name}')"

UP="$(kubectl -n "$NS" exec "$POD" -c scylla -- nodetool status \
  | grep -c '^UN' || true)"

echo "Cluster:  $CLUSTER"
echo "Expected: $EXPECTED   Up/Normal (UN): $UP"

if [ "$UP" -eq "$EXPECTED" ]; then
  echo "PASS"
else
  echo "FAIL"
  exit 1
fi
