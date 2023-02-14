#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# This script should create two outputs:
# - action: either "deploy", "remove", or "none"
# - path: the path the preview files will be located at (repo-name/{"pr" | "branch"}/{#})
# -----------------------------------------------------------------------------

event_name=$EVENT_NAME
event_type=$EVENT_TYPE
pr_number=$PR_NUMBER
ref_name=$REF_NAME
ref_type=$REF_TYPE
repo_name=$REPO_NAME

# Default value
echo "action=none" >>$GITHUB_OUTPUT

case $event_name in
"pull_request" | "pull_request_target")
  echo "Event name: $event_name; OK"

  echo "Event type: $event_type"

  case $event_type in
  "opened" | "reopened" | "synchronize")
    action="deploy"
    ;;
  "closed")
    action="remove"
    ;;
  *)
    action="none"
    ;;
  esac

  echo "PR number: $pr_number"

  path="$repo_name/pr/$pr_number"
  ;;

"push")
  echo "Event name: $event_name; OK"

  echo "Ref pushed: $ref_name ($ref_type)"

  if [[ $ref_type == branch ]]; then
    action="deploy"
    path="$repo_name/branch/$ref_name"
  else
    action="none"
    path=""
  fi
  ;;

"delete")
  echo "Event name: $event_name; OK"

  echo "Ref deleted: $ref_name ($ref_type)"

  if [[ $ref_type == branch ]]; then
    action="remove"
    path="$repo_name/branch/$ref_name"
  else
    action="none"
    path=""
  fi
  ;;

*)
  echo "::error::Event name: $event_name; NOT SUPPORTED"
  exit 1
  ;;
esac

echo "Resulting outputs:"
echo "action: $action"
echo "path: $path"

echo "action=$action" >>$GITHUB_OUTPUT
echo "path=$path" >>$GITHUB_OUTPUT
