package dictionary

import "unicode/utf8"

// BuildPrefixTree contructs a new prefix tree from the provided dictionary.
func BuildPrefixTree(d Interface) *PrefixTree {
	var root PrefixTree
	for _, w := range d.Words() {
		root.Insert(w)
	}
	return &root
}

// PrefixTree is a prefix tree/trie implementation that can be constructed from
// a dictionary.Interface.
type PrefixTree struct {
	Valid bool
	edges map[rune]*PrefixTree
}

// Assert that a PrefixTree is also a dictionary and implements Interface.
var _ Interface = &PrefixTree{}

// Contains returns true if the provided word is contained within the prefix tree.
func (t *PrefixTree) Contains(word string) bool {
	wordBytes := []byte(word)
	for len(wordBytes) > 0 {
		if t == nil {
			return false
		}

		c, size := utf8.DecodeRune(wordBytes)
		t = t.Next(c)
		wordBytes = wordBytes[size:]
	}
	return t.Valid
}

// Words returns a slice of all words contained within the prefix tree.
func (t *PrefixTree) Words() (words []string) {
	if t.Valid {
		words = append(words, "")
	}

	for r, n := range t.edges {
		for _, w := range n.Words() {
			words = append(words, string(r)+w)
		}
	}
	return words
}

// Next returns a new prefix tree, rooted at the next character.
func (t *PrefixTree) Next(c rune) *PrefixTree {
	if t.edges == nil {
		return nil
	}
	return t.edges[c]
}

// Insert inserts a new word into the prefix tree.
func (t *PrefixTree) Insert(s string) {
	if len(s) == 0 {
		t.Valid = true
		return
	}

	if t.edges == nil {
		t.edges = make(map[rune]*PrefixTree)
	}

	c, size := utf8.DecodeRune([]byte(s))
	rest := s[size:]

	if _, ok := t.edges[c]; !ok {
		t.edges[c] = &PrefixTree{}
	}
	t.edges[c].Insert(rest)
}
