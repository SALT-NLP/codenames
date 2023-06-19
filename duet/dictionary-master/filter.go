package dictionary

// Filter creates a new dictionary only containing words for which filterFunc
// returns true.
func Filter(source Interface, filterFunc func(string) bool) Interface {
	dict := &inMemory{
		words: make(map[string]struct{}),
	}

	for _, w := range source.Words() {
		if filterFunc(w) {
			dict.words[w] = struct{}{}
		}
	}

	return dict
}
