#!/bin/bash
set -euo pipefail

# ==============================================================================
# Load BuildPiper Base Functions
# ==============================================================================
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh

# ==============================================================================
# EVENTS TRACKING
# ==============================================================================
EVENTS='{}'

add_event() {
  local key="${1:-}"
  local status="${2:-}"
  local reason="${3:-}"
  local message="${4:-}"

  if [[ -z "$key" || -z "$status" ]]; then
    echo "Error: add_event requires key and status" >&2
    return 1
  fi

  key="$(echo "$key" \
      | tr '_' ' ' \
      | tr '-' ' ' \
      | tr '[:upper:]' '[:lower:]')"

  EVENTS=$(jq \
    --arg k "$key" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg message "$message" \
    '. + {
      ($k): {
        status: $status,
        reason: $reason,
        message: $message
      }
    }' <<< "$EVENTS")
}

# ==============================================================================
# Environment
# ==============================================================================
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"
EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"

MERGED_JSON="${REPORTS_DIR}/golint_report.json"
MERGED_CSV="${REPORTS_DIR}/golint_report.csv"

mkdir -p "${REPORTS_DIR}"
chmod -R 777 "${REPORTS_DIR}" || true

logInfoMessage "=============================================================="
logInfoMessage " Starting Golang Lint Analysis"
logInfoMessage "=============================================================="
logInfoMessage " Codebase location : ${CODEBASE_LOCATION}"
logInfoMessage " Reports directory : ${REPORTS_DIR}"
logInfoMessage "=============================================================="

# ==============================================================================
# Detect Go files
# ==============================================================================
logInfoMessage "Scanning repository for Go files..."

mapfile -t GO_FILES < <(
find "${CODEBASE_LOCATION}" -type f -name "*.go" \
-not -path "*/vendor/*" \
-not -path "*/build/*" \
-not -path "*/dist/*"
)

if [[ ${#GO_FILES[@]} -eq 0 ]]; then

    add_event "GO_LINT_FAILURE" "Failed" \
    "No Go files found" \
    "Workspace does not contain Go files"

    logWarningMessage "No Go files found"

    echo "{}" > "${MERGED_JSON}"
    echo "No Go files found" > "${MERGED_CSV}"

    mkdir -p "${EXEC_DIR}"

    cp "${MERGED_JSON}" "${EXEC_DIR}/"
    cp "${MERGED_CSV}" "${EXEC_DIR}/"

    exit 0
fi

logInfoMessage "Found ${#GO_FILES[@]} Go files."

# ==============================================================================
# Detect Go folders
# ==============================================================================
mapfile -t GO_FOLDERS < <(
for f in "${GO_FILES[@]}"; do
    dirname "$f"
done | sort -u
)

logInfoMessage "Found ${#GO_FOLDERS[@]} folder(s) with Go files."

add_event "PACKAGE_DISCOVERY" "Successful" \
"Go folders detected" \
"Found ${#GO_FOLDERS[@]} folders containing Go files"

echo "folder,total,high,medium,low" > "${MERGED_CSV}"

FIRST=true

echo "{" > "${MERGED_JSON}"

# ==============================================================================
# Run golangci-lint
# ==============================================================================
for folder in "${GO_FOLDERS[@]}"; do

    folder_name=$(basename "${folder}")

    RAW_JSON="${REPORTS_DIR}/${folder_name}_raw.json"

    logInfoMessage "--------------------------------------------------------------"
    logInfoMessage " Running lint on folder: ${folder}"
    logInfoMessage "--------------------------------------------------------------"

    add_event "GO_LINT_EXECUTION" "Successful" \
    "Running golangci-lint" \
    "Folder: ${folder}"

    STATUS=0

    (
      cd "${CODEBASE_LOCATION}"

      set +e

      golangci-lint run \
      --out-format json "${folder}/..." \
      > "${RAW_JSON}" 2>/dev/null

      STATUS=$?

      set -e
    )

    if [[ ! -s "${RAW_JSON}" ]]; then
        echo '{"Issues":[]}' > "${RAW_JSON}"
    fi

    chmod 777 "${RAW_JSON}" || true

    if [[ ${STATUS} -eq 1 ]]; then

        logWarningMessage "golangci-lint reported issues in ${folder}"

        add_event "GO_LINT_FAILURE" "Failed" \
        "Lint issues detected" \
        "Folder: ${folder}"

    elif [[ ${STATUS} -gt 1 ]]; then

        logWarningMessage "golangci-lint execution failed in ${folder}"

        add_event "GO_LINT_FAILURE" "Failed" \
        "golangci-lint execution failed" \
        "Folder: ${folder}"
    fi

    ISSUES=$(jq '.Issues // []' "${RAW_JSON}")

    TOTAL=$(echo "${ISSUES}" | jq 'length')

    HIGH=0
    MEDIUM=$(echo "${ISSUES}" | jq 'length')
    LOW=0

    ISSUES_JSON=$(echo "${ISSUES}" | jq '
    [
      .[] |
      {
        module:(.Pos.Filename | split("/") | .[0]),
        severity:"MEDIUM",
        rule_id:(.FromLinter // ""),
        details:(.Text // ""),
        file:(.Pos.Filename // ""),
        line:(.Pos.Line // 0)
      }
    ]
    ')

    echo "${folder_name},${TOTAL},${HIGH},${MEDIUM},${LOW}" \
    >> "${MERGED_CSV}"

    PKG_JSON=$(jq -n \
    --argjson total "$TOTAL" \
    --argjson high "$HIGH" \
    --argjson medium "$MEDIUM" \
    --argjson low "$LOW" \
    --argjson issues "$ISSUES_JSON" \
    '{
        total:$total,
        high:$high,
        medium:$medium,
        low:$low,
        issues:$issues
    }')

    if [[ "$FIRST" = true ]]; then
        FIRST=false
    else
        echo "," >> "${MERGED_JSON}"
    fi

    printf '"%s":%s\n' "$folder_name" "$PKG_JSON" \
    >> "${MERGED_JSON}"

done

echo "}" >> "${MERGED_JSON}"

chmod 777 "${MERGED_JSON}" || true
chmod 777 "${MERGED_CSV}" || true

# ==============================================================================
# Copy outputs
# ==============================================================================
mkdir -p "${EXEC_DIR}"

cp -f "${MERGED_JSON}" "${EXEC_DIR}/"
cp -f "${MERGED_CSV}" "${EXEC_DIR}/"

add_event "REPORT_GENERATED" "Successful" \
"Reports generated" \
"CSV and JSON reports created"

# ==============================================================================
# Cleanup
# ==============================================================================
find "${REPORTS_DIR}" -type f \
! -name "golint_report.json" \
! -name "golint_report.csv" \
-delete

add_event "GO_LINT_COMPLETE" "Successful" \
"Golang lint completed" \
"Execution completed successfully"

# ==============================================================================
# ERROR EVENTS
# ==============================================================================
ERROR_EVENTS=$(echo "${EVENTS}" | jq '
[
  to_entries[]
  | select(.value.status == "Failed")
  | .key
]')

# ==============================================================================
# OUTPUT JSON FOR BUILDPIPER EVENTS
# ==============================================================================
jq -n \
  --argjson events "${EVENTS}" \
  --argjson error_events "${ERROR_EVENTS}" \
'{
  build: {
    status: true,
    message: "Golang lint completed successfully",
    events: $events,
    error_events: $error_events
  }
}' > "${EXEC_DIR}/${ACTIVITY_SUB_TASK_CODE}_output.json"

chmod 777 "${EXEC_DIR}/${ACTIVITY_SUB_TASK_CODE}_output.json"

logInfoMessage "=============================================================="
logInfoMessage " Golang Lint Step Completed Successfully"
logInfoMessage "=============================================================="

exit 0
