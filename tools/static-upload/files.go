package main

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// File is one hash-named build file to upload.
type File struct {
	Name        string
	Body        []byte
	MD5         string // lowercase hex
	ContentType string
}

// hashedName is the file name pattern of a content-hashed build file. The
// Fastly condition for /static/build/ matches the same names.
var hashedName = regexp.MustCompile(`^[A-Za-z0-9_@-]+\.v[A-Za-z0-9_-]+\.(js|js\.map|css|svg|png)$`)

// skippedSymlinks are the unversioned names the build points at the current
// hashed files. They must be symlinks and are not uploaded.
var skippedSymlinks = []string{"app.js", "style.css", "d3-vendor.js"}

const (
	viteDir      = ".vite"
	manifestName = "manifest.json"
)

// contentTypes maps the extension group of hashedName to a Content-Type.
var contentTypes = map[string]string{
	"js":     "text/javascript; charset=utf-8",
	"js.map": "application/json",
	"css":    "text/css; charset=utf-8",
	"svg":    "image/svg+xml",
	"png":    "image/png",
}

// newFile returns the File for a hashed build file name and its content.
func newFile(name string, body []byte) (File, error) {
	m := hashedName.FindStringSubmatch(name)
	if m == nil {
		return File{}, fmt.Errorf("%s: not a hashed build file name", name)
	}
	ct, ok := contentTypes[m[1]]
	if !ok {
		return File{}, fmt.Errorf("%s: no content type for .%s", name, m[1])
	}
	sum := md5.Sum(body)
	return File{Name: name, Body: body, MD5: hex.EncodeToString(sum[:]), ContentType: ct}, nil
}

type manifestEntry struct {
	File   string   `json:"file"`
	CSS    []string `json:"css"`
	Assets []string `json:"assets"`
}

// SelectFiles returns the hash-named files in dir, sorted by name (the order
// os.ReadDir returns them in). Any entry that is not a hashed file, one of
// the skipped symlinks, or the Vite manifest makes it fail, as does a file
// the manifest names that is not there. The error lists every problem found.
func SelectFiles(dir string) ([]File, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var problems []string
	var files []File

	for _, e := range entries {
		name := e.Name()
		path := filepath.Join(dir, name)
		info, err := e.Info()
		if err != nil {
			return nil, err
		}

		switch {
		case name == viteDir:
			problems = append(problems, checkViteDir(path, info)...)

		case slices.Contains(skippedSymlinks, name):
			if info.Mode()&fs.ModeSymlink == 0 {
				problems = append(problems, fmt.Sprintf("%s: expected a symlink, found %s", name, describe(info)))
			}

		case !info.Mode().IsRegular():
			problems = append(problems, fmt.Sprintf("%s: unexpected %s", name, describe(info)))

		case !hashedName.MatchString(name):
			problems = append(problems, fmt.Sprintf("%s: not a hashed build file name", name))

		default:
			body, err := os.ReadFile(path)
			if err != nil {
				return nil, err
			}
			f, err := newFile(name, body)
			if err != nil {
				return nil, err
			}
			files = append(files, f)
		}
	}

	if len(files) == 0 {
		problems = append(problems, "no hashed files found")
	}

	referenced, err := manifestFiles(filepath.Join(dir, viteDir, manifestName))
	if err != nil {
		problems = append(problems, err.Error())
	}
	for _, name := range referenced {
		if !slices.ContainsFunc(files, func(f File) bool { return f.Name == name }) {
			problems = append(problems, fmt.Sprintf("%s: named in the manifest but not selected", name))
		}
	}

	if len(problems) > 0 {
		return nil, fmt.Errorf("%s:\n  %s", dir, strings.Join(problems, "\n  "))
	}

	return files, nil
}

// checkViteDir allows .vite/ to hold only manifest.json, as a regular file.
func checkViteDir(path string, info fs.FileInfo) []string {
	if !info.IsDir() {
		return []string{fmt.Sprintf("%s: expected a directory, found %s", viteDir, describe(info))}
	}
	entries, err := os.ReadDir(path)
	if err != nil {
		return []string{fmt.Sprintf("%s: %s", viteDir, err)}
	}
	var problems []string
	for _, e := range entries {
		name := viteDir + "/" + e.Name()
		info, err := e.Info()
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %s", name, err))
			continue
		}
		if e.Name() != manifestName || !info.Mode().IsRegular() {
			problems = append(problems, fmt.Sprintf("%s: unexpected %s", name, describe(info)))
		}
	}
	return problems
}

// manifestFiles returns every file, css and assets entry in the manifest.
func manifestFiles(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("%s/%s: missing", viteDir, manifestName)
		}
		return nil, err
	}
	var manifest map[string]manifestEntry
	if err := json.Unmarshal(b, &manifest); err != nil {
		return nil, fmt.Errorf("%s/%s: %w", viteDir, manifestName, err)
	}
	var names []string
	for _, e := range manifest {
		if e.File != "" {
			names = append(names, e.File)
		}
		names = append(names, e.CSS...)
		names = append(names, e.Assets...)
	}
	slices.Sort(names)
	return slices.Compact(names), nil
}

func describe(info fs.FileInfo) string {
	switch m := info.Mode(); {
	case m&fs.ModeSymlink != 0:
		return "symlink"
	case m.IsDir():
		return "directory"
	case m.IsRegular():
		return "regular file"
	default:
		return "file of mode " + m.String()
	}
}
