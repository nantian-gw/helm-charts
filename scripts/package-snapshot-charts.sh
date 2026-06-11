#!/usr/bin/env bash
set -euo pipefail

chart_dir="${CHART_DIR:-charts/nantian-gw}"
dist_dir="${DIST_DIR:-.dist}"
print_commits=false

usage() {
  cat <<'EOF'
Usage: package-snapshot-charts.sh [--print-commits]

Packages one immutable Helm chart snapshot for each commit in the current push.

Environment:
  CHART_DIR              Chart path inside the repository. Default: charts/nantian-gw
  DIST_DIR               Output directory. Default: .dist
  GITHUB_EVENT_BEFORE    Previous commit from the GitHub push event.
  GITHUB_SHA             Current push HEAD commit.
  SNAPSHOT_COMMITS       Optional whitespace-separated commit override for tests/manual runs.
EOF
}

while (($#)); do
  case "$1" in
    --print-commits)
      print_commits=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_zero_sha() {
  [[ "$1" =~ ^0+$ ]]
}

commit_exists() {
  git rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1
}

resolve_commits() {
  local before="${GITHUB_EVENT_BEFORE:-}"
  local head="${GITHUB_SHA:-}"
  local commits

  if [[ -n "${SNAPSHOT_COMMITS:-}" ]]; then
    # shellcheck disable=SC2086
    printf '%s\n' ${SNAPSHOT_COMMITS}
    return
  fi

  if [[ -z "$head" ]]; then
    head="$(git rev-parse HEAD)"
  fi

  if [[ -n "$before" ]] && ! is_zero_sha "$before" && commit_exists "$before"; then
    commits="$(git rev-list --reverse "${before}..${head}")"
    if [[ -n "$commits" ]]; then
      printf '%s\n' "$commits"
      return
    fi
  fi

  printf '%s\n' "$head"
}

validate_snapshot_chart() {
  local chart_path="$1"

  CHART_DIR="$chart_path" bash scripts/validate-chart-production.sh
}

package_snapshot() (
  local commit="$1"
  local short_sha version tmp_dir chart_path

  short_sha="$(git rev-parse --short "$commit")"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  git archive "$commit" "$chart_dir" | tar -x -C "$tmp_dir"
  chart_path="$tmp_dir/$chart_dir"

  if [[ ! -f "$chart_path/Chart.yaml" ]]; then
    echo "chart metadata not found for commit $commit at $chart_dir/Chart.yaml" >&2
    exit 1
  fi

  validate_snapshot_chart "$chart_path"

  version="$(awk '/^version:/ { print $2; exit }' "$chart_path/Chart.yaml")"
  if [[ -z "$version" ]]; then
    echo "chart version not found for commit $commit" >&2
    exit 1
  fi

  helm package "$chart_path" -d "$dist_dir" --version "${version}-${short_sha}"
)

mapfile -t commits < <(resolve_commits)

if [[ "${#commits[@]}" -eq 0 ]]; then
  echo "no commits resolved for snapshot packaging" >&2
  exit 1
fi

if [[ "$print_commits" == true ]]; then
  printf '%s\n' "${commits[@]}"
  exit 0
fi

mkdir -p "$dist_dir"
for commit in "${commits[@]}"; do
  package_snapshot "$commit"
done
