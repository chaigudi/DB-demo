#!/usr/bin/env bash
#
# Simple ScyllaDB backup tool: snapshot a keyspace and ship the SSTables to S3.
# RF=3 across 3 nodes means a single node's snapshot is a full copy of the data.
#
# The ScyllaDB container image has no `tar`, so we enumerate the snapshot files
# with `find`, stream each out with `cat`, and package + upload on the client
# side (which has tar + aws).
#
set -euo pipefail

NS="${NS:-scylla}"
KEYSPACE="${KEYSPACE:-demo}"
BUCKET="${BUCKET:-chaithu-backup-scylla}"
POD="${POD:-scylladb-dc1-us-east-1a-0}"
TAG="backup-$(date -u +%Y%m%d-%H%M%S)"
DEST="s3://${BUCKET}/${KEYSPACE}/${TAG}.tgz"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo ">> snapshot ${KEYSPACE} on ${POD} as ${TAG}"
kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool snapshot -t "${TAG}" "${KEYSPACE}"

echo ">> pulling SSTables (no tar in the scylla image; copying files individually)"
FILES="$(kubectl -n "${NS}" exec "${POD}" -c scylla -- \
  sh -c "cd /var/lib/scylla/data && find ${KEYSPACE} -type f -path '*/snapshots/${TAG}/*'")"

echo "${FILES}" | while IFS= read -r f; do
  [ -z "${f}" ] && continue
  mkdir -p "${WORK}/$(dirname "${f}")"
  kubectl -n "${NS}" exec "${POD}" -c scylla -- cat "/var/lib/scylla/data/${f}" > "${WORK}/${f}"
done

echo ">> packaging locally and uploading to ${DEST}"
tar czf - -C "${WORK}" "${KEYSPACE}" | aws s3 cp - "${DEST}"

echo ">> clearing on-node snapshot"
kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool clearsnapshot -t "${TAG}" "${KEYSPACE}"

echo ">> done: ${DEST}"
aws s3 ls "s3://${BUCKET}/${KEYSPACE}/"
