#!/usr/bin/env bash
set -e

GITHUB_API_URL="${API_URL:-https://api.github.com}"
GITHUB_SERVER_URL="${SERVER_URL:-https://github.com}"

validateArgs() {
  # Token I/P Check
  if [ -z "${INPUT_REPO_TOKEN}" ]
  then
    echo "Error: Repository token is required."
    exit 1
  fi

  # Brand Name Check (Required for fetching brand name)
  if [ -z "${INPUT_BRAND_NAME}" ]
  then
    echo "Error: Brandname is required"
    exit 1
  else 
    clientPayload=$(echo '{"brandName": "'"${INPUT_BRAND_NAME}"'"}' | jq -c)  
  fi

  # Setup variables
  ref="develop"
  org="AEMCS"
  repository="unilever-frontend-automation"
  workflowfile="package-generator-agency.yml"
  workflowId=null
}

api() {
  path=$1; shift
  if response=$(curl --fail-with-body -sSL \
      "${GITHUB_API_URL}/repos/${org}/${repository}/actions/$path" \
      -H "Authorization: Bearer ${INPUT_REPO_TOKEN}" \
      -H 'Accept: application/vnd.github.v3+json' \
      -H 'Content-Type: application/json' \
      "$@")
  then
    echo "$response"
  else
    echo >&2 "api failed:"
    echo >&2 "path: $path"
    echo >&2 "response: $response"
    if [[ "$response" == *'"Server Error"'* ]]; then 
      echo "Server error - trying again"
    else
      exit 1
    fi
  fi
}

getWorkflowData() {
  since=${1:?}
  query="event=workflow_dispatch&created=>=$since${GITHUB_ACTOR+&actor=}${GITHUB_ACTOR}"
  api "workflows/${workflowfile}/runs?${query}" |
  jq -r '[.workflow_runs[].id][0]'
}

triggerWorkflowHandler() {
  echo >&2 "Triggering Workflow For Syncing Platform"

  # Sleeping the thread for concurrency
  sleep 3

  # Trigger the workflow
  api "workflows/${workflowfile}/dispatches" \
    --data "{\"ref\":\"${ref}\",\"inputs\":${clientPayload}}"

  # Sleeping the thread as it takes few seconds to trigger the workflow
  sleep 3
  
  START_TIME=$(date +%s)
  SINCE=$(date -u -Iseconds -d "@$((START_TIME - 5))")  

  # Fetching the lastest workflow ID in last 5 seconds
  NEW_RUNS=$(getWorkflowData "$SINCE")

  workflowId=$NEW_RUNS
}

workflowStallHandler() {

  echo "Syncing the Platform Changes..."
  echo "It might take 3-4 minutes"

  # Setting up the flags for tracking
  isComplete=null
  currentStatus=

  # Checking the status of the workflow
  while [[ "${isComplete}" == "null" && "${currentStatus}" != "completed" ]]
  do
    workflow=$(api "runs/$workflowId")
    isComplete=$(echo "${workflow}" | jq -r '.conclusion')
    currentStatus=$(echo "${workflow}" | jq -r '.status')
  done

  # Workflow finished with success
  if [[ "${isComplete}" == "success" && "${currentStatus}" == "completed" ]]
  then
    echo "Platform Synced Successfully..."
    echo "Fetching The PR Link..."

    # Fetching the latest PR Link generated by workflow
    if response=$(curl -sSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${INPUT_REPO_TOKEN}"\
    -H "X-GitHub-Api-Version: 2022-11-28" \
    ${GITHUB_API_URL}/repos/${org}/theme-${INPUT_BRAND_NAME}/pulls?state=open | jq -r '[.[].html_url][0]')
    then
  
    if [[ ! -z "$response" ]] && [[ $response != "null" ]]
      then
        echo "PR Link": $response
      else
        echo "NO PR Found"  
    fi 
    else
    echo "PR Link Not Fetched Due To Some Error"
    fi
  else
    # Workflow finished with error
    echo "Platform syncing failed due to some error"
    exit 1
  fi
}

entrypoint() {
  # Step 1: Validate the required arguments
  validateArgs

    # Step 2: Fetch The Triggering The Workflow
    triggerWorkflowHandler

    # Step 3: Wait for the Job to be finished
    if [[ ! -z "$workflowId" ]] && [[ $workflowId != "null" ]]
      then
      workflowStallHandler
      else
      echo "Platform syncing failed due to no workflow triggered"
      exit 1
    fi  
}

entrypoint