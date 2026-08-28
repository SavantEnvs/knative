#!/usr/bin/env bash
#
# mayhem/test.sh — BEHAVIORAL oracle for Knative Serving's autoscaler config
# parser. Runs the dynamically-linked KAT probe (/mayhem/config_kat, built by
# build.sh) that parses fixed config maps through the real NewConfigFromMap()
# path and asserts the EXACT field values (derived from the parser's own
# defaults + coercion rules in pkg/autoscaler/config/config.go).
#
# Why not `go test` alone (netnew §4): a Go test binary is statically linked, so
# the gate's LD_PRELOAD sabotage shim cannot neuter it — the suite would survive
# sabotage while proving nothing. The KAT probe is cgo-linked (dynamic), so when
# the program is neutered to _exit(0) it prints nothing, every assertion below
# misses, and test.sh FAILS — which is the point (§6.3).
#
# Emits a CTRF summary; exits non-zero iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PROBE=/mayhem/config_kat
passed=0; failed=0

# Unconditional: a missing probe is a build.sh bug — FAIL loudly, never skip.
if [ ! -x "$PROBE" ]; then
  echo "FAIL: KAT probe $PROBE missing or not executable (build.sh should have produced it)" >&2
  emit_ctrf "knative-autoscaler-config-kat" 0 1
  exit 1
fi

OUT="$("$PROBE" 2>/dev/null)"
echo "--- KAT probe output ---"; printf '%s\n' "$OUT"; echo "------------------------"

# Fixed maps parsed through the real NewConfigFromMap; assert every result
# against the known answer (defaults + coercion rules in config.go).
assert() { # <desc> <expected-line>
  if printf '%s\n' "$OUT" | grep -qxF "$2"; then
    echo "PASS: $1"; passed=$((passed+1))
  else
    echo "FAIL: $1 (expected exact line: $2)"; failed=$((failed+1))
  fi
}

assert "default max-scale-up-rate == 1000"                 "KAT_0_OUT=1000"
assert "default requests-per-second-target == 200"         "KAT_1_OUT=200"
assert "max-scale-up-rate=3.5 parses to 3.5"               "KAT_2_OUT=3.5"
assert "container-concurrency-target-percentage=50 -> 0.5" "KAT_3_OUT=0.5"
assert "stable-window=70s -> 1m10s"                        "KAT_4_OUT=1m10s"
assert "pod-autoscaler-class passthrough"                  "KAT_5_OUT=custom.knative.dev"

emit_ctrf "knative-autoscaler-config-kat" "$passed" "$failed"
