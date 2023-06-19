package dictionary

import "testing"

func TestSliceContains(t *testing.T) {
	var testCases = []struct {
		words            []string
		shouldNotContain []string
	}{
		{
			words:            []string{"apple", "banana", "lemons", "zucchini"},
			shouldNotContain: []string{"orange", "bananana", "zucc"},
		},
		{
			words:            []string{"words", "games", "lemons"},
			shouldNotContain: []string{"orange", ""},
		},
		{
			words:            []string{},
			shouldNotContain: []string{"orange", ""},
		},
	}

	for _, tc := range testCases {
		d := WithWords(tc.words...)

		for _, w := range tc.words {
			if !d.Contains(w) {
				t.Errorf("Expected dictionary (%+v) to contain `%s`", d, w)
			}
		}

		for _, w := range tc.shouldNotContain {
			if d.Contains(w) {
				t.Errorf("Expected dictionary (%+v) to not contain `%s`", d, w)
			}
		}
	}
}
