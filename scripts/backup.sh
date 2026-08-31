#!/usr/bin/env bash
#
# ScyllaDB backup tool: snapshot a keyspace on EVERY node and ship the SSTables to S3.
#
set -euo pipefail

NS="${NS:-scylla}"
KEYSPACE="${KEYSPACE:-demo}"
BUCKET="${BUCKET:-chaithu-backup-scylla}"
SELECTOR="${SELECTOR:-scylla/cluster=scylladb}"
TAG="backup-$(date -u +%Y%m%d-%H%M%S)"
PREFIX="s3://${BUCKET}/${KEYSPACE}/${TAG}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PODS="$(kubectl -n "${NS}" get pods -l "${SELECTOR}" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')"
[ -n "${PODS}" ] || { echo "no running scylla pods matched selector ${SELECTOR}"; exit 1; }

echo ">> backup tag ${TAG}"
echo ">> nodes in scope: ${PODS}"
{ echo "keyspace=${KEYSPACE}"; echo "tag=${TAG}"; echo "taken_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "${WORK}/manifest.txt"

for POD in ${PODS}; do
  echo ">> [${POD}] snapshot"
  if ! kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool snapshot -t "${TAG}" "${KEYSPACE}" >/dev/null 2>&1; then
    echo ">> [${POD}] not reachable (skipping)"; echo "node=${POD} skipped=true" >> "${WORK}/manifest.txt"; continue
  fi

  echo ">> [${POD}] streaming snapshot files (single exec)"
  kubectl -n "${NS}" exec "${POD}" -c scylla -- sh -c '
    cd /var/lib/scylla/data || exit 0
    find '"${KEYSPACE}"' -path "*/snapshots/'"${TAG}"'/*" -type f | while IFS= read -r f; do
      echo "===F ${f}"; base64 "${f}"; echo "===E"
    done' > "${WORK}/${POD}.b64"

  NODE_WORK="${WORK}/nw-${POD}"; mkdir -p "${NODE_WORK}"
  file=""
  while IFS= read -r line; do
    case "${line}" in
      "===F "*) rel="${line#===F }"; mkdir -p "${NODE_WORK}/$(dirname "${rel}")"; file="${NODE_WORK}/${rel}"; : > "${file}.b64";;
      "===E")   [ -n "${file}" ] && { base64 -d "${file}.b64" > "${file}"; rm -f "${file}.b64"; file=""; };;
      *)        [ -n "${file}" ] && printf '%s\n' "${line}" >> "${file}.b64";;
    esac
  done < "${WORK}/${POD}.b64"

  if [ -d "${NODE_WORK}/${KEYSPACE}" ]; then
    echo ">> [${POD}] upload -> ${PREFIX}/${POD}.tgz"
    tar czf - -C "${NODE_WORK}" "${KEYSPACE}" | aws s3 cp - "${PREFIX}/${POD}.tgz"
    echo "node=${POD}" >> "${WORK}/manifest.txt"
  else
    echo ">> [${POD}] no data for ${KEYSPACE} on this node"
    echo "node=${POD} empty=true" >> "${WORK}/manifest.txt"
  fi

  kubectl -n "${NS}" exec "${POD}" -c scylla -- nodetool clearsnapshot -t "${TAG}" "${KEYSPACE}" >/dev/null
done

cat "${WORK}/manifest.txt" | aws s3 cp - "${PREFIX}/manifest.txt"
echo ">> done. backup at ${PREFIX}/"
aws s3 ls "${PREFIX}/"
