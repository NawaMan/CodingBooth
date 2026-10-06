// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package hostescape

import (
	"strings"
	"testing"
)

func TestFormat_NoReasons_Empty(t *testing.T) {
	if got := Format(nil); got != "" {
		t.Fatalf("no reasons must format to nothing, got %q", got)
	}
}

func TestFormat_EachReasonHasImpactAndLink(t *testing.T) {
	got := Format([]Reason{
		{Kind: KindHostMounts, What: "writable mount of host /run/media/me/disk"},
		{Kind: KindHostNetwork, What: "--network=host"},
	})
	for _, want := range []string{
		"This booth has settings that let code inside it reach the host:",
		"  - writable mount of host /run/media/me/disk\n      " + Impact(KindHostMounts, WhereHost) + "\n      " + DocURL + "#host-mounts\n",
		"  - --network=host\n      " + Impact(KindHostNetwork, WhereHost) + "\n      " + DocURL + "#host-network\n",
		"This only matters if the booth runs code you do not trust.",
		"If you trust what it runs, go ahead.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "as root") {
		t.Errorf("neither reason leads to root, got:\n%s", got)
	}
}

func TestEveryKindHasItsOwnImpact(t *testing.T) {
	seen := map[string]Kind{}
	for _, kind := range []Kind{KindDind, KindEngineSocket, KindKernelAccess, KindHostMounts, KindHomeMounts, KindHostNetwork} {
		impact := Impact(kind, WhereHost)
		if other, dup := seen[impact]; dup {
			t.Errorf("%s and %s share an impact line", kind, other)
		}
		seen[impact] = kind
		if !strings.HasPrefix(impact, "Untrusted code in the booth could ") {
			t.Errorf("%s: impact should be conditional on untrusted code: %q", kind, impact)
		}
	}
}

func TestLabel_RoundTrip(t *testing.T) {
	reasons := []Reason{{Kind: KindDind, What: "--dind (x)"}, {Kind: KindHomeMounts, What: `writable mount of host /home/me/.m2, "q"`}}
	got := DecodeLabel(EncodeLabel(reasons))
	if len(got) != 2 || got[0] != reasons[0] || got[1] != reasons[1] {
		t.Fatalf("round trip lost data: %v", got)
	}
	if EncodeLabel(nil) != "" {
		t.Fatal("no reasons must encode to no label")
	}
	for _, bad := range []string{"", "  ", "not json", "{}"} {
		if DecodeLabel(bad) != nil {
			t.Errorf("%q should decode to no reasons", bad)
		}
	}
}

func TestImpact_DependsOnWhere(t *testing.T) {
	for _, kind := range []Kind{KindDind, KindEngineSocket, KindKernelAccess} {
		if !strings.Contains(Impact(kind, WhereVM), "engine's Linux VM (not this machine itself)") {
			t.Errorf("%s on a VM engine should say VM: %q", kind, Impact(kind, WhereVM))
		}
		if !strings.Contains(Impact(kind, WhereWSL), "other WSL distros") {
			t.Errorf("%s on WSL should mention the other WSL distros: %q", kind, Impact(kind, WhereWSL))
		}
		if strings.Contains(Impact(kind, WhereAccount), "as root") {
			t.Errorf("%s rootless must not claim root: %q", kind, Impact(kind, WhereAccount))
		}
	}
	if Impact(KindHomeMounts, WhereVM) != Impact(KindHomeMounts, WhereHost) {
		t.Error("a home mount is code as you on every engine")
	}
}

func TestLabel_KeepsWhere(t *testing.T) {
	got := DecodeLabel(EncodeLabel([]Reason{{Kind: KindKernelAccess, What: "--privileged", Where: WhereWSL}}))
	if len(got) != 1 || got[0].Where != WhereWSL {
		t.Fatalf("where lost: %v", got)
	}
	if got := DecodeLabel(`[{"kind":"dind","what":"x"}]`); len(got) != 1 || got[0].Where != WhereHost {
		t.Fatalf("a label without where (older booth) reads as the host: %v", got)
	}
}
