#!/bin/bash
set -euo pipefail

# ==============================================================================
#  Load BuildPiper Base Functions
# ==============================================================================
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/getDataFile.sh

# ==============================================================================
#  Environment
# ==============================================================================
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"
EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"

mkdir -p "${REPORTS_DIR}"
chmod -R 0777 "${REPORTS_DIR}" 2>/dev/null || true

logInfoMessage "=============================================================="
logInfoMessage " Starting Golang Lint Analysis"
logInfoMessage "=============================================================="
logInfoMessage " Codebase location : ${CODEBASE_LOCATION}"
logInfoMessage " Reports directory : ${REPORTS_DIR}"
logInfoMessage "=============================================================="

# ------------------------------------------------------------------------------
#  Scan repo for Go files
# ------------------------------------------------------------------------------
logInfoMessage "Scanning repository for Go files..."

mapfile -t GO_FILES < <(
    find "${CODEBASE_LOCATION}" -type f -name "*.go" \
        -not -path "*/vendor/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*"
)

if [[ ${#GO_FILES[@]} -eq 0 ]]; then
    logWarningMessage "No Go files found. Skipping lint."
    echo "{}" > "${REPORTS_DIR}/golint_report.json"
    echo "No Go files found" > "${REPORTS_DIR}/golint_report.csv"
    exit 0
fi

logInfoMessage "Found ${#GO_FILES[@]} Go files."

# ------------------------------------------------------------------------------
#  Identify folders that contain Go files
# ------------------------------------------------------------------------------
mapfile -t GO_FOLDERS < <(
    for f in "${GO_FILES[@]}"; do
        dirname "$f"
    done | sort -u
)

logInfoMessage "Found ${#GO_FOLDERS[@]} folder(s) with Go files."

# ------------------------------------------------------------------------------
# Run golangci-lint per folder
# ------------------------------------------------------------------------------
for folder in "${GO_FOLDERS[@]}"; do
    folder_name=$(basename "${folder}")
    folder_name_safe=$(echo "$folder_name" | tr '/' '_' | tr ' ' '_')

    JSON_OUT="${REPORTS_DIR}/golint_${folder_name_safe}.json"
    CSV_OUT="${REPORTS_DIR}/golint_${folder_name_safe}.csv"

    logInfoMessage "--------------------------------------------------------------"
    logInfoMessage " Running lint on folder: ${folder}"
    logInfoMessage " JSON report: ${JSON_OUT}"
    logInfoMessage " CSV report : ${CSV_OUT}"
    logInfoMessage "--------------------------------------------------------------"

    set +e
    golangci-lint run \
        --out-format json:"${JSON_OUT}",line-number:"${CSV_OUT}" \
        --timeout=5m \
        "${folder}" >/dev/null 2>&1
    STATUS=$?
    set -e

    [[ $STATUS -ne 0 ]] && logWarningMessage "golangci-lint reported issues in ${folder}"

    [[ ! -s "${JSON_OUT}" ]] && echo "{}" > "${JSON_OUT}"
    [[ ! -s "${CSV_OUT}" ]] && echo "No issues found" > "${CSV_OUT}"
done

# ------------------------------------------------------------------------------
# Merge all CSVs → golint_report.csv
# ------------------------------------------------------------------------------
MERGED_CSV="${REPORTS_DIR}/golint_report.csv"
logInfoMessage "Merging all CSV reports into: ${MERGED_CSV}"

: > "${MERGED_CSV}"
first_file=true

for csv_file in "${REPORTS_DIR}"/golint_*.csv; do
    [[ "$csv_file" == "${MERGED_CSV}" ]] && continue
    [[ ! -s "$csv_file" ]] && continue

    if $first_file; then
        cat "$csv_file" >> "${MERGED_CSV}"
        first_file=false
    else
        tail -n +2 "$csv_file" >> "${MERGED_CSV}"
    fi
done

[[ ! -s "${MERGED_CSV}" ]] && echo "No lint results found" > "${MERGED_CSV}"

# ------------------------------------------------------------------------------
# Merge all JSONs → golint_report.json
# ------------------------------------------------------------------------------
MERGED_JSON="${REPORTS_DIR}/golint_report.json"
logInfoMessage "Merging all JSON reports into: ${MERGED_JSON}"

echo "{" > "${MERGED_JSON}"
first=true

for json_file in "${REPORTS_DIR}"/golint_*.json; do
    [[ "$json_file" == "${MERGED_JSON}" ]] && continue

    folder_key=$(basename "$json_file" | sed 's/^golint_//' | sed 's/\.json$//')
    json_content=$(cat "$json_file")

    if $first; then
        first=false
    else
        echo "," >> "${MERGED_JSON}"
    fi

    echo "\"${folder_key}\": ${json_content}" >> "${MERGED_JSON}"
done

echo "}" >> "${MERGED_JSON}"

# ------------------------------------------------------------------------------
# Cleanup: delete only individual JSON + CSV files (NOT merged files)
# ------------------------------------------------------------------------------
logInfoMessage "Cleaning up individual report files..."

for f in "${REPORTS_DIR}"/golint_*.json; do
    [[ "$f" == "${MERGED_JSON}" ]] && continue
    rm -f "$f"
done

for f in "${REPORTS_DIR}"/golint_*.csv; do
    [[ "$f" == "${MERGED_CSV}" ]] && continue
    rm -f "$f"
done

logInfoMessage "Cleanup completed."

# ------------------------------------------------------------------------------
# Copy final merged reports to execution dir
# ------------------------------------------------------------------------------
mkdir -p "${EXEC_DIR}"
cp -f "${MERGED_CSV}" "${EXEC_DIR}/"
cp -f "${MERGED_JSON}" "${EXEC_DIR}/"

logInfoMessage "Copied final reports → ${EXEC_DIR}"

logInfoMessage "=============================================================="
logInfoMessage " Golang Lint Step Completed Successfully"
logInfoMessage "=============================================================="
