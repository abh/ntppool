package main

import (
	"crypto/md5"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const validManifest = `{"src/main.ts":{"file":"app.vAbc_1.js","css":["style.vDef-2.css"],"assets":["logo-2019@x2.vGh3.png"]}}`

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func symlink(t *testing.T, target, path string) {
	t.Helper()
	if err := os.Symlink(target, path); err != nil {
		t.Fatal(err)
	}
}

// validDir builds a directory shaped like a client build.
func validDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, ".vite", "manifest.json"), validManifest)
	writeFile(t, filepath.Join(dir, "app.vAbc_1.js"), "console.log('app')\n")
	writeFile(t, filepath.Join(dir, "app.vAbc_1.js.map"), `{"version":3}`)
	writeFile(t, filepath.Join(dir, "style.vDef-2.css"), "body{}\n")
	writeFile(t, filepath.Join(dir, "logo-2019@x2.vGh3.png"), "\x89PNG")
	symlink(t, "app.vAbc_1.js", filepath.Join(dir, "app.js"))
	symlink(t, "style.vDef-2.css", filepath.Join(dir, "style.css"))
	symlink(t, "app.vAbc_1.js", filepath.Join(dir, "d3-vendor.js"))
	return dir
}

func wantError(t *testing.T, err error, contains string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected an error containing %q, got nil", contains)
	}
	if !strings.Contains(err.Error(), contains) {
		t.Fatalf("error %q does not contain %q", err, contains)
	}
}

func TestSelectFilesValid(t *testing.T) {
	dir := validDir(t)
	files, err := SelectFiles(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, f := range files {
		names = append(names, f.Name)
	}
	want := []string{"app.vAbc_1.js", "app.vAbc_1.js.map", "logo-2019@x2.vGh3.png", "style.vDef-2.css"}
	if !slices.Equal(names, want) {
		t.Fatalf("names = %v, want %v", names, want)
	}
	wantTypes := map[string]string{
		"app.vAbc_1.js":         "text/javascript; charset=utf-8",
		"app.vAbc_1.js.map":     "application/json",
		"logo-2019@x2.vGh3.png": "image/png",
		"style.vDef-2.css":      "text/css; charset=utf-8",
	}
	for _, f := range files {
		if f.ContentType != wantTypes[f.Name] {
			t.Errorf("%s: content type %q, want %q", f.Name, f.ContentType, wantTypes[f.Name])
		}
		body, err := os.ReadFile(filepath.Join(dir, f.Name))
		if err != nil {
			t.Fatal(err)
		}
		if string(f.Body) != string(body) {
			t.Errorf("%s: body differs from the file on disk", f.Name)
		}
		if want := fmt.Sprintf("%x", md5.Sum(body)); f.MD5 != want {
			t.Errorf("%s: MD5 %q, want %q", f.Name, f.MD5, want)
		}
	}
}

func TestNewFileSVG(t *testing.T) {
	f, err := newFile("wrld.vA9KUVn69.svg", nil)
	if err != nil || f.ContentType != "image/svg+xml" {
		t.Fatalf("newFile(svg) = %q, %v", f.ContentType, err)
	}
}

func TestSelectFilesRejectsUnversioned(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, "extra.js"), "x")
	_, err := SelectFiles(dir)
	wantError(t, err, "extra.js")
}

func TestSelectFilesRejectsUnknownExt(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, "font.vX1.woff2"), "x")
	_, err := SelectFiles(dir)
	wantError(t, err, "font.vX1.woff2")
}

func TestSelectFilesRejectsSubdir(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, "sub", "a.vX1.js"), "x")
	_, err := SelectFiles(dir)
	wantError(t, err, "sub")
}

func TestSelectFilesRejectsExtraViteFile(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, ".vite", "other.json"), "{}")
	_, err := SelectFiles(dir)
	wantError(t, err, "other.json")
}

func TestSelectFilesRejectsOtherSymlink(t *testing.T) {
	dir := validDir(t)
	symlink(t, "app.vAbc_1.js", filepath.Join(dir, "alias.vX1.js"))
	_, err := SelectFiles(dir)
	wantError(t, err, "alias.vX1.js")
}

func TestSelectFilesRejectsRegularSkipName(t *testing.T) {
	dir := validDir(t)
	if err := os.Remove(filepath.Join(dir, "app.js")); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(dir, "app.js"), "x")
	_, err := SelectFiles(dir)
	wantError(t, err, "app.js")
}

func TestSelectFilesListsEveryBadEntry(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, "extra.js"), "x")
	writeFile(t, filepath.Join(dir, "font.vX1.woff2"), "x")
	_, err := SelectFiles(dir)
	wantError(t, err, "extra.js")
	wantError(t, err, "font.vX1.woff2")
}

func TestSelectFilesEmptyDir(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, ".vite", "manifest.json"), "{}")
	_, err := SelectFiles(dir)
	wantError(t, err, "no hashed files")
}

func TestSelectFilesManifestEntryMissing(t *testing.T) {
	dir := validDir(t)
	writeFile(t, filepath.Join(dir, ".vite", "manifest.json"),
		`{"src/main.ts":{"file":"app.vAbc_1.js","css":["style.vDef-2.css"],"assets":["logo-2019@x2.vGh3.png"]},`+
			`"src/zone-chart.ts":{"file":"zone-chart.vZz9.js"}}`)
	_, err := SelectFiles(dir)
	wantError(t, err, "zone-chart.vZz9.js")
}

func TestSelectFilesNoManifest(t *testing.T) {
	dir := validDir(t)
	if err := os.Remove(filepath.Join(dir, ".vite", "manifest.json")); err != nil {
		t.Fatal(err)
	}
	_, err := SelectFiles(dir)
	wantError(t, err, "manifest.json")
}
