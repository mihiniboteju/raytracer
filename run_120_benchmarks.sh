#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT_DIR"

RESULTS_DIR="$ROOT_DIR/preliminary_results/full_$(date -u +%Y%m%dT%H%M%SZ)"
CSV="$RESULTS_DIR/results.csv"
DIAGNOSTICS="$RESULTS_DIR/diagnostics.log"
BACKUP="$RESULTS_DIR/main.cpp.backup"
RUN_STDERR="$RESULTS_DIR/current_run.stderr"
mkdir -p "$RESULTS_DIR"
cp src/main.cpp "$BACKUP"

restore_source() {
  cp "$BACKUP" src/main.cpp
  rm -f "$RUN_STDERR"
}
trap restore_source EXIT INT TERM HUP

fail() {
  printf 'ERROR: %s\n' "$*" | tee -a "$DIAGNOSTICS" >&2
  if [[ -f "$RUN_STDERR" ]]; then
    printf '%s\n' '--- failed run stderr ---' >>"$DIAGNOSTICS"
    cat "$RUN_STDERR" >>"$DIAGNOSTICS"
  fi
  exit 1
}

set_bunny_spp() {
  local spp=$1
  SPP="$spp" perl -0pi -e '
    my $spp = $ENV{SPP};
    my $count = 0;
    s{
      (void\s+bunny\s*\(\s*\)\s*\{.*?\n)
      ((?:(?!void\s+\w+\s*\(\s*\)\s*\{).)*?)
      (\bcamera\.samples_per_pixel\s*=\s*)\d+(\s*;)
    }{
      $count++;
      $1 . $2 . $3 . $spp . $4
    }gsex;
    die "expected exactly one bunny SPP assignment, found $count\n"
      if $count != 1;
  ' src/main.cpp
}

verify_configuration() {
  local spp=$1
  grep -Eq 'switch[[:space:]]*\([[:space:]]*3[[:space:]]*\)' src/main.cpp ||
    fail "active scene is not switch (3)"
  awk -v spp="$spp" '
    /void bunny[[:space:]]*\([[:space:]]*\)[[:space:]]*\{/ {
      in_bunny=1
      depth=0
    }
    in_bunny {
      if ($0 ~ /camera\.aspect_ratio[[:space:]]*=[[:space:]]*16\.0[[:space:]]*\/[[:space:]]*9\.0/) aspect=1
      if ($0 ~ /camera\.image_width[[:space:]]*=[[:space:]]*300[[:space:]]*;/) width=1
      if ($0 ~ ("camera\\.samples_per_pixel[[:space:]]*=[[:space:]]*" spp "[[:space:]]*;")) spp_ok=1
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0 && NR > 1) exit
    }
    END { exit !(aspect && width && spp_ok) }
  ' src/main.cpp || fail "bunny configuration mismatch for SPP=$spp"
}

extract_time() {
  awk '
    /^OMP parallel execution time: [0-9]+([.][0-9]+)? seconds$/ {
      count++
      value=$5
    }
    END {
      if (count != 1 || value <= 0) exit 1
      print value
    }
  '
}

printf 'workload,spp,threads,run,time_seconds\n' >"$CSV"

for config in "1x 2" "2x 4" "4x 8"; do
  read -r workload spp <<<"$config"
  set_bunny_spp "$spp"
  verify_configuration "$spp"
  make clean >>"$DIAGNOSTICS" 2>&1 || fail "make clean failed for SPP=$spp"
  make OPENMP=1 >>"$DIAGNOSTICS" 2>&1 || fail "build failed for SPP=$spp"

  for threads in 1 2 3 4; do
    for run in $(seq 1 10); do
      : >"$RUN_STDERR"
      if ! OMP_NUM_THREADS="$threads" ./build/raytracer >/dev/null 2>"$RUN_STDERR"; then
        fail "render failed: workload=$workload spp=$spp threads=$threads run=$run"
      fi
      if ! time_seconds=$(extract_time <"$RUN_STDERR"); then
        fail "expected exactly one positive timing: workload=$workload spp=$spp threads=$threads run=$run"
      fi
      printf '%s,%s,%s,%s,%s\n' \
        "$workload" "$spp" "$threads" "$run" "$time_seconds" >>"$CSV"
      printf '%s SPP=%s threads=%s run=%s: %s seconds\n' \
        "$workload" "$spp" "$threads" "$run" "$time_seconds"
    done
  done
done

rows=$(awk 'NR > 1 { count++ } END { print count+0 }' "$CSV")
[[ "$rows" -eq 120 ]] || fail "expected 120 data rows, found $rows"
printf 'Completed 120 timing tests. Results: %s\n' "$CSV"
