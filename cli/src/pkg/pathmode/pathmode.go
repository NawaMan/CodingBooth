// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package pathmode reads the optional permission suffix on a cache-dirs /
// shared-dirs entry ("home/coder/.gnupg:0700") and creates such a directory.
//
// A ':' cannot appear in a container mount path (Docker uses it as the -v
// separator), so the last ':' in an entry always starts the suffix. The suffix
// is octal permission bits only. It applies when the directory is created; a
// directory that already exists keeps whatever mode it has.
package pathmode

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Split separates an entry into its path and mode. Mode is 0 when the entry has
// no suffix. A suffix that is not 3-4 octal digits within 0777 is an error.
func Split(entry string) (string, os.FileMode, error) {
	i := strings.LastIndex(entry, ":")
	if i < 0 {
		return entry, 0, nil
	}
	path, suffix := entry[:i], entry[i+1:]
	if len(suffix) < 3 || len(suffix) > 4 {
		return "", 0, fmt.Errorf("invalid mode %q in %q: want octal like 0700", suffix, entry)
	}
	mode, err := strconv.ParseUint(suffix, 8, 32)
	if err != nil || mode > 0o777 {
		return "", 0, fmt.Errorf("invalid mode %q in %q: want octal like 0700", suffix, entry)
	}
	if mode == 0 {
		return "", 0, fmt.Errorf("invalid mode %q in %q: a directory no one can open", suffix, entry)
	}
	return path, os.FileMode(mode), nil
}

// Path is Split without the error: the entry's path, or the entry itself when
// its suffix does not parse. For display and for computing where a directory
// goes, where the entry was already validated (or an error is reported elsewhere).
func Path(entry string) string {
	path, _, err := Split(entry)
	if err != nil {
		return entry
	}
	return path
}

// MkdirAll creates dir (and its parents, 0755) when it does not exist, then
// sets mode on dir itself when mode is not 0. An existing dir is left as is.
func MkdirAll(dir string, mode os.FileMode) error {
	if _, err := os.Stat(dir); err == nil {
		return nil
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	if mode != 0 {
		return os.Chmod(dir, mode)
	}
	return nil
}
