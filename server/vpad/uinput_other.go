//go:build !linux

package vpad

import "errors"

// NewUinput only works on Linux. Use -dry on other platforms for development.
func NewUinput(name string) (Pad, error) {
	return nil, errors.New("uinput is only available on Linux")
}
