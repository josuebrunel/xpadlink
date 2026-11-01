//go:build !linux

// xpadrumble needs Linux force feedback (evdev).
package main

import "fmt"

func main() { fmt.Println("xpadrumble only works on Linux") }
