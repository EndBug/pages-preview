#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Wait for the preview-repo Pages workflow to land our changes.
#
# The preview repo uses a single concurrency group, so a pending run is
# cancelled when a newer one is queued (even with cancel-in-progress: false).
# That later run deploys the whole site, so a cancelled run is not a failure
# if a successor deploy includes our commit and preview path.
#
# Outputs:
# - conclusion: success | cancelled | failure | timed_out | ...
# -----------------------------------------------------------------------------

set -euo pipefail

export GH_PAGER=cat
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/dev/null}

GH_REPO_OWNER=${GH_REPO_OWNER:-}
GH_REPO_NAME=${GH_REPO_NAME:-}
WORKFLOW_FILE=${WORKFLOW_FILE:-preview.yml}
OUR_RUN_ID=${OUR_RUN_ID:-}
OUR_CONCLUSION=${OUR_CONCLUSION:-}
OUR_SHA=${OUR_SHA:-}
OUR_PATH=${OUR_PATH:-}
PREVIEW_ACTION=${PREVIEW_ACTION:-}
PREVIEW_BRANCH=${PREVIEW_BRANCH:-gh-pages}
WAIT_INTERVAL=${WAIT_INTERVAL:-10}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-1200}

log() {
  echo ">>>" "$@" >&2
}

write_conclusion() {
  echo "conclusion=$1" >>"$GITHUB_OUTPUT"
  echo "conclusion: $1"
}

succeed() {
  write_conclusion "success"
  exit 0
}

fail() {
  local conclusion=${1:-failure}
  write_conclusion "$conclusion"
  exit 1
}

is_cancelled() {
  [[ "$1" == "cancelled" || "$1" == "canceled" ]]
}

get_run() {
  gh api "/repos/${GH_REPO_OWNER}/${GH_REPO_NAME}/actions/runs/$1"
}

list_workflow_runs() {
  local encoded
  encoded=$(jq -nr --arg f "$WORKFLOW_FILE" '$f | @uri')
  gh api "/repos/${GH_REPO_OWNER}/${GH_REPO_NAME}/actions/workflows/${encoded}/runs?event=workflow_dispatch&per_page=50"
}

wait_for_run_completion() {
  local run_id=$1
  local payload status conclusion

  while (( $(date +%s) < deadline )); do
    payload=$(get_run "$run_id")
    status=$(jq -r '.status' <<<"$payload")
    conclusion=$(jq -r '.conclusion // empty' <<<"$payload")
    log "Run $run_id status=$status conclusion=${conclusion:-null}"
    if [[ "$status" == "completed" ]]; then
      echo "$conclusion"
      return 0
    fi
    sleep "$WAIT_INTERVAL"
  done

  log "Timed out waiting for run $run_id"
  return 1
}

preview_tree_matches() {
  if ! git fetch origin "$PREVIEW_BRANCH"; then
    log "Failed to fetch origin/$PREVIEW_BRANCH"
    return 1
  fi

  if ! git merge-base --is-ancestor "$OUR_SHA" "origin/$PREVIEW_BRANCH"; then
    log "Commit $OUR_SHA is not an ancestor of origin/$PREVIEW_BRANCH"
    return 1
  fi

  if git rev-parse --verify --quiet "origin/${PREVIEW_BRANCH}:${OUR_PATH}" >/dev/null; then
    if [[ "$PREVIEW_ACTION" == "deploy" ]]; then
      return 0
    fi
    log "Path $OUR_PATH still exists after a remove"
    return 1
  fi

  if [[ "$PREVIEW_ACTION" == "remove" ]]; then
    return 0
  fi

  log "Path $OUR_PATH is missing after a deploy"
  return 1
}

classify_runs() {
  jq -c --argjson our_id "$OUR_RUN_ID" '
    def active:
      .status == "queued" or
      .status == "in_progress" or
      .status == "waiting" or
      .status == "pending" or
      .status == "requested";

    [.workflow_runs[]? | {id, status, conclusion, html_url}]
    | {
        newer_active: [.[] | select(.id > $our_id and active)] | sort_by(.id) | reverse,
        newer_success: [.[] | select(.id > $our_id and .conclusion == "success")] | sort_by(.id) | reverse,
        newer_failure: [
          .[]
          | select(
              .id > $our_id and
              (.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")
            )
        ],
        newer_cancelled: [
          .[]
          | select(
              .id > $our_id and
              (.conclusion == "cancelled" or .conclusion == "canceled")
            )
        ],
        older_active: [.[] | select(.id <= $our_id and active)] | sort_by(.id) | reverse
      }
  '
}

wait_for_successor() {
  local classified newer_active_id newer_active_url newer_success_id older_active_id successor_conclusion
  local idle_cancelled_polls=0

  log "Triggered preview run $OUR_RUN_ID was cancelled; waiting for a successor deploy"

  while (( $(date +%s) < deadline )); do
    classified=$(list_workflow_runs | classify_runs)

    newer_active_id=$(jq -r '.newer_active[0].id // empty' <<<"$classified")
    newer_active_url=$(jq -r '.newer_active[0].html_url // empty' <<<"$classified")
    if [[ -n "$newer_active_id" ]]; then
      idle_cancelled_polls=0
      log "Waiting for newer run $newer_active_id that took priority ($newer_active_url)"
      if ! successor_conclusion=$(wait_for_run_completion "$newer_active_id"); then
        fail "timed_out"
      fi
      log "Successor run $newer_active_id concluded with $successor_conclusion"
      continue
    fi

    newer_success_id=$(jq -r '.newer_success[0].id // empty' <<<"$classified")
    if [[ -n "$newer_success_id" ]]; then
      log "Found successful successor run $newer_success_id"
      if preview_tree_matches; then
        log "Successor deploy includes our preview changes"
        succeed
      fi
      log "Successor run succeeded but the preview tree does not match this action"
      fail "failure"
    fi

    if [[ "$(jq -r '.newer_failure | length' <<<"$classified")" -gt 0 ]]; then
      log "Successor preview deploy failed"
      fail "failure"
    fi

    older_active_id=$(jq -r '.older_active[0].id // empty' <<<"$classified")
    if [[ -n "$older_active_id" ]]; then
      idle_cancelled_polls=0
      log "No newer run yet; waiting for in-progress run $older_active_id"
      if ! wait_for_run_completion "$older_active_id" >/dev/null; then
        fail "timed_out"
      fi
      continue
    fi

    if [[ "$(jq -r '.newer_cancelled | length' <<<"$classified")" -gt 0 ]]; then
      idle_cancelled_polls=$((idle_cancelled_polls + 1))
      if (( idle_cancelled_polls >= 3 )); then
        log "Successor preview runs were also cancelled"
        fail "cancelled"
      fi
    fi

    log "No successor run listed yet; retrying"
    sleep "$WAIT_INTERVAL"
  done

  log "Timed out waiting for a successor preview deploy"
  fail "timed_out"
}

if [[ -z "$GH_REPO_OWNER" || -z "$GH_REPO_NAME" ]]; then
  log "Preview repo owner/name are required"
  fail "failure"
fi

if [[ -z "$OUR_SHA" || -z "$OUR_PATH" || -z "$PREVIEW_ACTION" ]]; then
  log "OUR_SHA, OUR_PATH, and PREVIEW_ACTION are required"
  fail "failure"
fi

if [[ -z "$OUR_CONCLUSION" || "$OUR_CONCLUSION" == "null" ]]; then
  if [[ -z "$OUR_RUN_ID" ]]; then
    log "No preview workflow run was triggered"
    fail "failure"
  fi
  OUR_CONCLUSION=$(jq -r '.conclusion // empty' <<<"$(get_run "$OUR_RUN_ID")")
fi

log "Preview workflow conclusion: ${OUR_CONCLUSION:-unknown} (run ${OUR_RUN_ID:-none})"

if [[ "$OUR_CONCLUSION" == "success" ]]; then
  succeed
fi

if [[ "$OUR_CONCLUSION" == "failure" || "$OUR_CONCLUSION" == "timed_out" || "$OUR_CONCLUSION" == "startup_failure" ]]; then
  fail "$OUR_CONCLUSION"
fi

if ! is_cancelled "$OUR_CONCLUSION"; then
  log "Unexpected preview workflow conclusion: $OUR_CONCLUSION"
  fail "$OUR_CONCLUSION"
fi

if [[ ! "$OUR_RUN_ID" =~ ^[0-9]+$ ]]; then
  log "Invalid preview workflow run id: ${OUR_RUN_ID:-empty}"
  fail "cancelled"
fi

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
wait_for_successor
