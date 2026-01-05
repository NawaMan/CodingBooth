package ilist

import (
	"testing"
)

func TestSemicolonStringList_Decode(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{"Empty", "", []string{}},
		{"Whitespace", "   ", []string{}},
		{"Single", "a", []string{"a"}},
		{"Multiple", "a;b;c", []string{"a", "b", "c"}},
		{"TrimEdges", " a ; b ; c ", []string{"a", "b", "c"}},
		{"SkipEmpty", "a;;b", []string{"a", "b"}},
		{"Complex", " a ; ; b ; c ", []string{"a", "b", "c"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var list SemicolonStringList
			err := list.Decode(tt.input)
			if err != nil {
				t.Fatalf("Decode failed: %v", err)
			}

			if list.Length() != len(tt.expected) {
				t.Errorf("Length() = %d, want %d", list.Length(), len(tt.expected))
			}

			for i, want := range tt.expected {
				if got, _ := list.Get(i); got != want {
					t.Errorf("Get(%d) = %q, want %q", i, got, want)
				}
			}
		})
	}
}

func TestSemicolonStringList_Clone(t *testing.T) {
	var list SemicolonStringList
	list.Decode("original")

	cloned := list.Clone()

	// Verify deep copy by checking values
	if cloned.Length() != 1 {
		t.Errorf("Cloned Length() = %d, want 1", cloned.Length())
	}
	if v, _ := cloned.Get(0); v != "original" {
		t.Errorf("Cloned Get(0) = %q, want 'original'", v)
	}

	// Verify independence (we can't easily mutate List[string] externally without unsafe or re-decoding)
	// Re-decode original
	list.Decode("modified")

	if v, _ := cloned.Get(0); v != "original" {
		t.Errorf("Cloned list affected by original modification: got %q", v)
	}
}
