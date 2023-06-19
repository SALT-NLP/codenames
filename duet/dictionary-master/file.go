package dictionary

import (
	"errors"
	"io/ioutil"
	"strings"
)

var (
	// DefaultDictionaryNotFound is an error returned when the default system dictionary
	// cannot be found or loaded.
	DefaultDictionaryNotFound = errors.New("Unable to find default dictionary")

	dictionaryLocations = []string{
		"/usr/share/dict/words",
		"/usr/dict/words",
	}
)

// Default returns the default dictionary on Unix systems.
func Default() (Interface, error) {
	for _, filename := range dictionaryLocations {
		d, err := Load(filename)
		if err == nil {
			return d, nil
		}
	}

	return nil, DefaultDictionaryNotFound
}

// Load loads a dictionary from a file containing newline separated words.
func Load(filename string) (Interface, error) {
	b, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	return WithWords(strings.Split(strings.TrimSpace(string(b)), "\n")...), nil
}
