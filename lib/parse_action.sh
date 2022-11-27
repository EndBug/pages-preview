#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# This script should create two outputs:
# - action: either "deploy", "remove", or "none"
# - path: the path the preview files will be located at (repo-name/{"pr" | "branch"}/{#})
# -----------------------------------------------------------------------------

event_name=$EVENT_NAME
event_payload=$EVENT_PAYLOAD
repo_name=$REPO_NAME

# Default value
echo "action=none" >>$GITHUB_OUTPUT

case $event_name in
"pull_request" | "pull_request_target")
  echo "Event name: $event_name; OK"

  event_type=$(jq .action <<<$event_payload | sed -e 's/^"//' -e 's/"$//')
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

  pr_number=$(jq .number <<<$event_payload | sed -e 's/^"//' -e 's/"$//')
  echo "PR number: $pr_number"

  path="$repo_name/pr/$pr_number"
  ;;

"push")
  echo "Event name: $event_name; OK"

  ref=$(jq .ref <<<$event_payload | sed -e 's/^"//' -e 's/"$//')
  echo "Ref pushed: $ref"

  if [[ ref == refs/heads/* ]]; then
    action="deploy"
    branch=${ref#refs/heads/}
    path="$repo_name/branch/$branch"
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
