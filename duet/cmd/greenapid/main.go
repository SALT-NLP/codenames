package main

import (
	"os"
	"net/http"
	"codenamesgreen/gameapi"
	"fmt"
)

func main() {
	wordLists, err := gameapi.DefaultWordlists()
	if err != nil {
		panic(err)
	}
	h := gameapi.Handler(wordLists)
	port := os.Getenv("PORT")
	// PORT env should not be set on EC2
	if port == "" {
		port = "8080"
	}
	fmt.Print("Using port: " + port)
	err = http.ListenAndServe(":" + port, h)
	panic(err)
}
