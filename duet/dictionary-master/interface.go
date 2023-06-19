// Package dictionary provides utilities for working with dictionary words.
package dictionary

// Interface defines the interface that all dictionaries implement.
type Interface interface {
	// Contains determines if the provided word is contained within the dictionary.
	Contains(string) bool

	// Words returns a slice of all of the words contained in the dictionary.
	Words() []string
}
