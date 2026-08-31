#!/usr/bin/env bash
#
# Restore a ScyllaDB backup made by backup.sh (per-node SSTables in S3).
#
set -euo pipefail

NS="${NS:-scylla}"
KEYSPACE="${KEYSPACE:-demo}"
BUCKET="${BUCKET:-chaithu-backup-scylla}"
POD="${POD:-scylladb-dc1-us-east-1a-0}"
COUNT_TABLE="${COUNT_TABLE:-users}"
TAG="${1:?usage: restore.sh <backup-tag>   e.g. restore.sh backup-20260831-165447}"

DATA="/var/lib/scylla/data"
PREFIX="s3://${BUCKET}/${KEYSPACE}/${TAG}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo ">> reading backup manifest ${PREFIX}/manifest.txt"
aws s3 cp "${PREFIX}/manifest.txt" - > "${WORK}/manifest.txt" 2>/dev/null && cat "${WORK}/manifest.txt" || echo "(no manifest, continuing)"

ARTIFACTS="$(aws s3 ls "${PREFIX}/" | awk '/\.tgz$/ {print $4}')"
[ -n "${ARTIFACTS}" ] || { echo "no per-node .tgz artifacts under ${PREFIX}/"; exit 1; }

for art in ${ARTIFACTS}; do
  echo ">> === loading ${art} ==="
  rm -rf "${WORK}/x"; mkdir -p "${WORK}/x"
  aws s3 cp "${PREFIX}/${art}" - > "${WORK}/n.tgz"
  tar xzf "${WORK}/n.tgz" -C "${WORK}/x"

  for tabdir in "${WORK}/x/${KEYSPACE}"/*/; do
    [ -d "${tabdir}" ] || continue
    table="$(basename "${tabdir}" | sed -E 's/-[0-9a-f]{32}$//')"
    snap="$(find "${tabdir}snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    [ -n "${snap}" ] || { echo "   skip ${table} (no snapshot files)"; continue; }

    live="$(kubectl -n "${NS}" exec "${POD}" -c scylla -- \
      sh -c "ls -d ${DATA}/${KEYSPACE}/${table}-* 2>/dev/null | head -1" | tr -d '\r')"
    if [ -z "${live}" ]; then
      echo "   ERROR: table ${KEYSPACE}.${table} does not exist on the target."
      echo "          Recreate the schema (CREATE TABLE) first, then re-run."
      exit 1
    fi

    echo "   loading ${table} -> ${live}/upload (single exec)"
    { for f in "${snap}"/*; do
        [ -f "${f}" ] || continue
        echo "===F $(basename "${f}")"; base64 "${f}"; echo "===E"
      done; } | kubectl -n "${NS}" exec -i "${POD}" -c scylla -- sh -c '
        cd "'"${live}"'/upload" 2>/dev/null || { mkdir -p "'"${live}"'/upload"; cd "'"${live}"'/upload"; }
        file=""
        while IFS= read -r line; do
          case "${line}" in
            "===F "*) file="${line#===F }"; : > "${file}.b64";;
            "===E")   [ -n "${file}" ] && { base64 -d "${file}.b64" > "${file}"; rm -f "${file}.b64"; file=""; };;
            *)        [ -n "${file}" ] && printf "%s\n" "${line}" >> "${file}.b64";;
          esac
        done'

    kubectl -n "${NS}" exec "${POD}" -c scylla -- \
      nodetool refresh --load-and-stream "${KEYSPACE}" "${table}"
  done
done

echo ">> restore complete. row count in ${KEYSPACE}.${COUNT_TABLE}:"
kubectl -n "${NS}" exec -i "${POD}" -c scylla -- \
  cqlsh -u cassandra -p cassandra -e "SELECT COUNT(*) FROM ${KEYSPACE}.${COUNT_TABLE};"
