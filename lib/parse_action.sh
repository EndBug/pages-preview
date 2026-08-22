#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# This script creates outputs:
# - action: either "deploy", "remove", or "none"
# - path: the path the preview files will be located at (repo-name/{"pr" | "branch"}/{#})
# - pr_number: the resolved PR number, or empty when the path is not a PR preview
# -----------------------------------------------------------------------------

event_name=${EVENT_NAME:-}
event_type=${EVENT_TYPE:-}
event_pr_number=${EVENT_PR_NUMBER:-}
event_ref=${EVENT_REF:-}
event_ref_type=${EVENT_REF_TYPE:-}
repo_name=${REPO_NAME:-}

input_action=${INPUT_ACTION:-}
input_pr_number=${INPUT_PR_NUMBER:-}
input_ref=${INPUT_REF:-}
input_ref_type=${INPUT_REF_TYPE:-}

normalize_ref_name() {
  local ref=$1
  if [[ $ref == refs/* ]]; then
    cut -d "/" -f 3- <<<"$ref"
  else
    echo "$ref"
  fi
}

path_from_inputs=false
path_kind=""
resolved_pr_number=""
resolved_ref_name=""
resolved_ref_type=""

if [[ -n "$input_pr_number" ]]; then
  path_from_inputs=true
  path_kind="pr"
  resolved_pr_number="$input_pr_number"
elif [[ -n "$input_ref" ]]; then
  path_from_inputs=true
  path_kind="branch"
  resolved_ref_name=$(normalize_ref_name "$input_ref")
  if [[ -n "$input_ref_type" ]]; then
    resolved_ref_type="$input_ref_type"
  else
    resolved_ref_type="branch"
  fi
else
  case $event_name in
  "pull_request" | "pull_request_target")
    path_kind="pr"
    if [[ -z "$event_pr_number" ]]; then
      echo "::error::pr_number is required when the event is pull_request/pull_request_target and was not provided via inputs or payload"
      exit 1
    fi
    resolved_pr_number="$event_pr_number"
    ;;
  "push" | "delete")
    path_kind="branch"
    resolved_ref_name=$(cut -d "/" -f 3- <<<"$event_ref")
    resolved_ref_type="$event_ref_type"
    ;;
  *)
    echo "::error::Either pr_number or ref must be provided when the event is not pull_request, pull_request_target, push, or delete"
    exit 1
    ;;
  esac
fi

echo "Event name: $event_name"
echo "Event type: $event_type"
echo "Path kind: $path_kind"
echo "Path from inputs: $path_from_inputs"

action=""
path=""

if [[ $path_kind == "pr" ]]; then
  echo "PR number: $resolved_pr_number"
  path="$repo_name/pr/$resolved_pr_number"
elif [[ $path_kind == "branch" ]]; then
  echo "Ref: $resolved_ref_name ($resolved_ref_type)"

  if [[ $resolved_ref_type == "branch" ]]; then
    path="$repo_name/branch/$resolved_ref_name"
  else
    action="none"
    path=""
  fi
fi

if [[ -n "$input_action" ]]; then
  if [[ "$input_action" != "deploy" && "$input_action" != "remove" ]]; then
    echo "::error::action must be deploy or remove, got: $input_action"
    exit 1
  fi

  if [[ -n "$path" ]]; then
    action="$input_action"
  else
    action="none"
  fi
elif [[ -z "$action" ]]; then
  case $event_name in
  "pull_request" | "pull_request_target")
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
    ;;
  "push")
    if [[ $resolved_ref_type == "branch" ]]; then
      action="deploy"
    else
      action="none"
    fi
    ;;
  "delete")
    if [[ $resolved_ref_type == "branch" ]]; then
      action="remove"
    else
      action="none"
    fi
    ;;
  *)
    if [[ $path_from_inputs == true && -n "$path" ]]; then
      echo "::error::action is required when pr_number or ref is provided via inputs on an event that does not define deploy or remove"
      exit 1
    fi
    action="none"
    ;;
  esac
fi

echo "Resulting outputs:"
echo "action: $action"
echo "path: $path"
echo "pr_number: $resolved_pr_number"

echo "action=$action" >>$GITHUB_OUTPUT
echo "path=$path" >>$GITHUB_OUTPUT
echo "pr_number=$resolved_pr_number" >>$GITHUB_OUTPUT
