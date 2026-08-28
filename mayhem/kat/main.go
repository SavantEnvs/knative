// mayhem/kat/main.go — dynamically-linked known-answer probe for Knative
// Serving's autoscaler config parser. `import "C"` (cgo) forces a DYNAMICALLY
// LINKED binary so the gate's LD_PRELOAD sabotage shim can neuter it; a
// statically-linked Go binary (what plain `go test` produces) would be immune,
// giving a false-green oracle — exactly the trap netnew §4 warns about.
//
// It calls the real, EXPORTED NewConfigFromMap() on fixed config maps and prints
// each asserted field in a fixed, greppable format for mayhem/test.sh. Every
// expected value below is derived from the parser's own defaults + coercion
// rules in pkg/autoscaler/config/config.go (defaultConfig + the %⇒fraction
// adjustment), so the oracle asserts the authors' documented behavior. When the
// program is neutered (_exit(0)) the probe prints nothing, every assertion
// misses, and test.sh FAILS — which is the point (§6.3).
package main

// #include <stdint.h>
import "C"

import (
	"fmt"
	"os"
	"strconv"

	asconfig "knative.dev/serving/pkg/autoscaler/config"
)

func mustParse(data map[string]string) map[string]string {
	cfg, err := asconfig.NewConfigFromMap(data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "KAT error: NewConfigFromMap(%v): %v\n", data, err)
		os.Exit(1)
	}
	if cfg == nil {
		fmt.Fprintf(os.Stderr, "KAT error: nil config for %v\n", data)
		os.Exit(1)
	}
	// Return a formatted view of every field the KAT asserts.
	return map[string]string{
		"MaxScaleUpRate":                     strconv.FormatFloat(cfg.MaxScaleUpRate, 'g', -1, 64),
		"RPSTargetDefault":                   strconv.FormatFloat(cfg.RPSTargetDefault, 'g', -1, 64),
		"ContainerConcurrencyTargetFraction": strconv.FormatFloat(cfg.ContainerConcurrencyTargetFraction, 'g', -1, 64),
		"StableWindow":                       cfg.StableWindow.String(),
		"PodAutoscalerClass":                 cfg.PodAutoscalerClass,
	}
}

func main() {
	defaults := mustParse(map[string]string{})
	rate := mustParse(map[string]string{"max-scale-up-rate": "3.5"})
	pct := mustParse(map[string]string{"container-concurrency-target-percentage": "50"})
	win := mustParse(map[string]string{"stable-window": "70s"})
	class := mustParse(map[string]string{"pod-autoscaler-class": "custom.knative.dev"})

	// Fixed inputs parsed through the real NewConfigFromMap; each result asserted
	// in mayhem/test.sh against the known answer.
	print := func(i int, expr, out string) {
		fmt.Printf("KAT_%d_EXPR=%s\n", i, expr)
		fmt.Printf("KAT_%d_OUT=%s\n", i, out)
	}
	print(0, "default MaxScaleUpRate", defaults["MaxScaleUpRate"])                           // 1000
	print(1, "default RPSTargetDefault", defaults["RPSTargetDefault"])                       // 200
	print(2, "max-scale-up-rate=3.5", rate["MaxScaleUpRate"])                                // 3.5
	print(3, "container-concurrency-target-percentage=50 -> fraction", pct["ContainerConcurrencyTargetFraction"]) // 0.5
	print(4, "stable-window=70s", win["StableWindow"])                                       // 1m10s
	print(5, "pod-autoscaler-class=custom.knative.dev", class["PodAutoscalerClass"])         // custom.knative.dev
}
