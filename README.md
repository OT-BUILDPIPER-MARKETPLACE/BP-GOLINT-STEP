# Golang Lint Analysis (Offline)

This BuildPiper step runs **golangci-lint** on all Go folders, merges results, and exports final reports.

---

## Setup

**Build Image:**

```
docker build -t ot/golint-analysis:0.1 .
```

**Run:**

```
docker run -it --rm \
  -v $PWD:/src \
  -e WORKSPACE="/src" \
  -e CODEBASE_DIR="." \
  -e GLOBAL_TASK_ID="local" \
  ot/golint-analysis:0.1
```

**Debug:**

```
docker run -it --rm -v $PWD:/src --entrypoint sh ot/golint-analysis:0.1
```

---

## What This Step Does

* Finds all `.go` files
* Detects folders containing Go code
* Runs **golangci-lint** per folder
* Generates per-folder JSON & CSV reports
* Merges everything into:

  * `golint_report.json`
  * `golint_report.csv`
* Copies merged files to:

```
/bp/execution_dir/${GLOBAL_TASK_ID}
```

---

## Inputs

No required input files. Code is scanned automatically from:

```
${WORKSPACE}/${CODEBASE_DIR}
```

---

## Output Files

Inside `<codebase>/reports/`:

* `golint_report.json`
* `golint_report.csv`

Exported to execution dir:

```
/bp/execution_dir/${GLOBAL_TASK_ID}/
```

---

## Notes

* Uses **golangci-lint v1.60.1**
* Folder exclusions: `vendor`, `build`, `dist`
* Runs as non-root `buildpiper` user

---

## Example BuildPiper Usage

```
WORKSPACE=/bp/workspace
CODEBASE_DIR=myservice
```

Reports generated under:

```
/bp/workspace/myservice/reports/
```
