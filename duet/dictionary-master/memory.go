package dictionary

import "strings"

type inMemory struct {
	words map[string]struct{}
}

// Assert that inMemory implements dictionary.Interface.
var _ Interface = &inMemory{}

// WithWords creates a new dictionary with the provided words.
func WithWords(words ...string) Interface {
	dict := &inMemory{
		words: make(map[string]struct{}),
	}

	for _, w := range words {
		dict.words[strings.ToUpper(w)] = struct{}{}
	}

	return dict
}

// Contains determines if the provided word is contained within the dictionary.
func (d *inMemory) Contains(w string) bool {
	w = strings.ToUpper(w)

	_, ok := d.words[w]
	return ok
}

// Words implements dictionary.Interface.
func (d *inMemory) Words() []string {
	words := make([]string, 0, len(d.words))

	for w := range d.words {
		words = append(words, w)
	}

	return words
}
