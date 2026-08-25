#!/usr/bin/env bash

set -euo pipefail

NS="${NS:-scylla}"
KEYSPACE="${KEYSPACE:-demo}"
BUCKET="${BUCKET:-chaithu-backup-scylla}"
POD="${POD:-scylladb-dc1-us-east-1a-0}"
TAG="backup-$(date -u +%Y%m%d-%H%M%S)"
DEST="s3://${BUCKET}/${KEYSPACE}/${TAG}.tgz"

echo ">> Snapshotting keyspace '${KEYSPACE}' on pod '${POD}' as tag '${TAG}'"
kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool snapshot -t "${TAG}" "${KEYSPACE}"

echo ">> Streaming SSTables to ${DEST}"
kubectl -n "${NS}" exec "${POD}" -c scylla -- \
  bash -c "cd /var/lib/scylla/data && tar czf - \$(find ${KEYSPACE} -type d -path '*/snapshots/${TAG}')" \
  | aws s3 cp - "${DEST}"

echo ">> Removing on-node snapshot (hardlinks) to reclaim space"
kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool clearsnapshot -t "${TAG}" "${KEYSPACE}"

echo ">> Done. Backup stored at ${DEST}"
echo ">> Current backups:"
aws s3 ls "s3://${BUCKET}/${KEYSPACE}/"
