#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT_DIR"

OUTPUT_DIR="$ROOT_DIR/preliminary_results/images"
BACKUP=$(mktemp)
cp src/main.cpp "$BACKUP"

restore_source() {
  cp "$BACKUP" src/main.cpp
  rm -f "$BACKUP"
}
trap restore_source EXIT INT TERM HUP

fail() {
  printf 'ERROR: %s\n' "$*" >&2
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

verify_bunny_configuration() {
  local spp=$1
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
  ' src/main.cpp || fail "bunny configuration validation failed for SPP=$spp"
}

validate_ppm() {
  local image=$1
  [[ -s "$image" ]] || fail "image is missing or empty: $image"
  mapfile -t header < <(head -n 3 "$image")
  [[ "${#header[@]}" -eq 3 ]] || fail "PPM header is incomplete: $image"
  [[ "${header[0]}" == "P3" ]] || fail "invalid PPM magic in $image"
  [[ "${header[1]}" == "300 168" ]] || fail "invalid dimensions in $image: ${header[1]}"
  [[ "${header[2]}" == "255" ]] || fail "invalid max color in $image"
}

mkdir -p "$OUTPUT_DIR"

for config in "2 bunny_spp2.ppm" "4 bunny_spp4.ppm" "8 bunny_spp8.ppm"; do
  read -r spp filename <<<"$config"
  image="$OUTPUT_DIR/$filename"
  log="${image%.ppm}.log"

  set_bunny_spp "$spp"
  verify_bunny_configuration "$spp"
  make clean && make OPENMP=1

  if ! OMP_NUM_THREADS=1 ./build/raytracer >"$image" 2>"$log"; then
    fail "render failed for SPP=$spp; see $log"
  fi
  validate_ppm "$image"
  printf 'Validated SPP=%s: %s (timing log: %s)\n' "$spp" "$image" "$log"
done
