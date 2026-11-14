package main

import (
	"context"
	"errors"
	"slices"
	"testing"
)

func TestSyncUploadsMissing(t *testing.T) {
	s := newFakeStore()
	files := []File{testFile("a.vX.js", "a"), testFile("b.vY.css", "b")}
	res, err := Sync(context.Background(), s, "build/", files)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"put build/a.vX.js", "put build/b.vY.css"}; !slices.Equal(s.writes, want) {
		t.Fatalf("writes = %v, want %v", s.writes, want)
	}
	if want := []string{"build/a.vX.js", "build/b.vY.css"}; !slices.Equal(res.Uploaded, want) {
		t.Fatalf("Uploaded = %v, want %v", res.Uploaded, want)
	}
	if len(res.Refreshed) != 0 {
		t.Fatalf("Refreshed = %v, want none", res.Refreshed)
	}
	for _, f := range files {
		obj := s.objects["build/"+f.Name]
		if obj.contentType != f.ContentType {
			t.Errorf("%s: content type %q, want %q", f.Name, obj.contentType, f.ContentType)
		}
	}
}

func TestSyncRefreshesIdentical(t *testing.T) {
	s := newFakeStore()
	f := testFile("a.vX.js", "a")
	s.objects["build/a.vX.js"] = fakeObject{etag: f.MD5, contentType: "application/octet-stream"}
	res, err := Sync(context.Background(), s, "build/", []File{f})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"refresh build/a.vX.js"}; !slices.Equal(s.writes, want) {
		t.Fatalf("writes = %v, want %v", s.writes, want)
	}
	if want := []string{"build/a.vX.js"}; !slices.Equal(res.Refreshed, want) {
		t.Fatalf("Refreshed = %v, want %v", res.Refreshed, want)
	}
	if len(res.Uploaded) != 0 {
		t.Fatalf("Uploaded = %v, want none", res.Uploaded)
	}
	if ct := s.objects["build/a.vX.js"].contentType; ct != f.ContentType {
		t.Fatalf("content type after refresh = %q, want %q", ct, f.ContentType)
	}
}

func TestSyncDifferentContentFails(t *testing.T) {
	s := newFakeStore()
	// a.vX.js sorts first, so a write before the conflict check would show.
	s.objects["build/b.vX.js"] = fakeObject{etag: "0123456789abcdef0123456789abcdef"}
	files := []File{testFile("a.vX.js", "a"), testFile("b.vX.js", "b")}
	_, err := Sync(context.Background(), s, "build/", files)
	wantError(t, err, "build/b.vX.js")
	if w := s.writes; len(w) != 0 {
		t.Fatalf("writes = %v, want none", w)
	}
}

func TestSyncListsEveryConflict(t *testing.T) {
	s := newFakeStore()
	s.objects["build/a.vX.js"] = fakeObject{etag: "0123456789abcdef0123456789abcdef"}
	s.objects["build/b.vX.js"] = fakeObject{etag: "0123456789abcdef0123456789abcdef"}
	files := []File{testFile("a.vX.js", "a"), testFile("b.vX.js", "b")}
	_, err := Sync(context.Background(), s, "build/", files)
	wantError(t, err, "build/a.vX.js")
	wantError(t, err, "build/b.vX.js")
}

func TestSyncHeadErrorIsFatal(t *testing.T) {
	s := newFakeStore()
	s.headErr["build/b.vX.js"] = errors.New("403 Forbidden")
	files := []File{testFile("a.vX.js", "a"), testFile("b.vX.js", "b")}
	_, err := Sync(context.Background(), s, "build/", files)
	wantError(t, err, "403 Forbidden")
	if w := s.writes; len(w) != 0 {
		t.Fatalf("writes = %v, want none", w)
	}
}

func TestSyncMultipartETagFails(t *testing.T) {
	s := newFakeStore()
	f := testFile("a.vX.js", "a")
	s.objects["build/a.vX.js"] = fakeObject{etag: f.MD5 + "-2"}
	_, err := Sync(context.Background(), s, "build/", []File{f})
	wantError(t, err, "build/a.vX.js")
	if w := s.writes; len(w) != 0 {
		t.Fatalf("writes = %v, want none", w)
	}
}

func TestSyncWriteErrorNamesKey(t *testing.T) {
	s := newFakeStore()
	s.putErr["build/a.vX.js"] = errors.New("boom")
	files := []File{testFile("a.vX.js", "a"), testFile("b.vX.js", "b")}
	_, err := Sync(context.Background(), s, "build/", files)
	wantError(t, err, "build/a.vX.js")
	if want := []string{"put build/a.vX.js"}; !slices.Equal(s.writes, want) {
		t.Fatalf("writes = %v, want %v", s.writes, want)
	}
}

func TestSyncKeepsDifferentMap(t *testing.T) {
	s := newFakeStore()
	const storedETag = "0123456789abcdef0123456789abcdef"
	js, m := testFile("a.vX.js", "a"), testFile("a.vX.js.map", `{"version":3}`)
	s.objects["build/a.vX.js"] = fakeObject{etag: js.MD5}
	s.objects["build/a.vX.js.map"] = fakeObject{etag: storedETag}
	res, err := Sync(context.Background(), s, "build/", []File{js, m})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"refresh build/a.vX.js", "refresh build/a.vX.js.map"}; !slices.Equal(s.writes, want) {
		t.Fatalf("calls = %v, want %v", s.writes, want)
	}
	if s.objects["build/a.vX.js.map"].etag != storedETag {
		t.Fatal("stored map was overwritten")
	}
	if want := []string{"build/a.vX.js.map"}; !slices.Equal(res.KeptMaps, want) {
		t.Fatalf("KeptMaps = %v, want %v", res.KeptMaps, want)
	}
	want := []Object{{Key: "build/a.vX.js", ETag: js.MD5}, {Key: "build/a.vX.js.map", ETag: storedETag}}
	if !slices.Equal(res.Stored, want) {
		t.Fatalf("Stored = %v, want %v", res.Stored, want)
	}
}

func TestSyncStoredIsLocalMD5(t *testing.T) {
	s := newFakeStore()
	a, b := testFile("a.vX.js", "a"), testFile("b.vX.css", "b")
	s.objects["build/b.vX.css"] = fakeObject{etag: b.MD5}
	res, err := Sync(context.Background(), s, "build/", []File{a, b})
	if err != nil {
		t.Fatal(err)
	}
	want := []Object{{Key: "build/a.vX.js", ETag: a.MD5}, {Key: "build/b.vX.css", ETag: b.MD5}}
	if !slices.Equal(res.Stored, want) {
		t.Fatalf("Stored = %v, want %v", res.Stored, want)
	}
}

func TestSyncDifferentJSStillFailsNextToMap(t *testing.T) {
	s := newFakeStore()
	const other = "0123456789abcdef0123456789abcdef"
	js, m := testFile("a.vX.js", "a"), testFile("a.vX.js.map", "{}")
	s.objects["build/a.vX.js"] = fakeObject{etag: other}
	s.objects["build/a.vX.js.map"] = fakeObject{etag: other}
	_, err := Sync(context.Background(), s, "build/", []File{js, m})
	wantError(t, err, "build/a.vX.js:")
	if len(s.writes) != 0 {
		t.Fatalf("calls = %v, want none", s.writes)
	}
}
