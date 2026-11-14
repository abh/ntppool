package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestWaitReplicatedImmediate(t *testing.T) {
	r := newFakeStore()
	files := []File{testFile("a.vX.js", "a"), testFile("b.vX.js", "b")}
	for _, f := range files {
		r.objects["build/"+f.Name] = fakeObject{etag: f.MD5}
	}
	if err := WaitReplicated(context.Background(), r, stored(files), time.Second, time.Millisecond); err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		if n := r.heads["build/"+f.Name]; n != 1 {
			t.Errorf("%s: %d HEADs, want 1", f.Name, n)
		}
	}
}

func TestWaitReplicatedEventually(t *testing.T) {
	r := newFakeStore()
	a, b := testFile("a.vX.js", "a"), testFile("b.vX.js", "b")
	r.objects["build/a.vX.js"] = fakeObject{etag: a.MD5}
	r.pending["build/b.vX.js"] = pendingObject{obj: fakeObject{etag: b.MD5}, at: 3}
	if err := WaitReplicated(context.Background(), r, stored([]File{a, b}), time.Second, time.Millisecond); err != nil {
		t.Fatal(err)
	}
	if n := r.heads["build/a.vX.js"]; n != 1 {
		t.Errorf("a: %d HEADs, want 1 (only pending keys are checked again)", n)
	}
	if n := r.heads["build/b.vX.js"]; n != 3 {
		t.Errorf("b: %d HEADs, want 3", n)
	}
}

func TestWaitReplicatedTimeout(t *testing.T) {
	r := newFakeStore()
	a, b := testFile("a.vX.js", "a"), testFile("b.vX.js", "b")
	r.objects["build/a.vX.js"] = fakeObject{etag: a.MD5}
	err := WaitReplicated(context.Background(), r, stored([]File{a, b}), 20*time.Millisecond, time.Millisecond)
	wantError(t, err, "build/b.vX.js")
	wantError(t, err, "missing")
	if contains := "build/a.vX.js"; err != nil && strings.Contains(err.Error(), contains) {
		t.Errorf("error %q names %s, which was replicated", err, contains)
	}
}

func TestWaitReplicatedWrongETag(t *testing.T) {
	r := newFakeStore()
	a := testFile("a.vX.js", "a")
	r.objects["build/a.vX.js"] = fakeObject{etag: "0123456789abcdef0123456789abcdef"}
	err := WaitReplicated(context.Background(), r, stored([]File{a}), 20*time.Millisecond, time.Millisecond)
	wantError(t, err, "build/a.vX.js")
	wantError(t, err, "ETag differs")
}

func TestWaitReplicatedHeadErrorIsRetried(t *testing.T) {
	r := newFakeStore()
	a := testFile("a.vX.js", "a")
	r.headErr["build/a.vX.js"] = errors.New("503 Slow Down")
	err := WaitReplicated(context.Background(), r, stored([]File{a}), 20*time.Millisecond, time.Millisecond)
	wantError(t, err, "503 Slow Down")
	if n := r.heads["build/a.vX.js"]; n < 2 {
		t.Errorf("%d HEADs, want the error retried", n)
	}
}

func TestWaitReplicatedCancelled(t *testing.T) {
	r := newFakeStore()
	a := testFile("a.vX.js", "a")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := WaitReplicated(ctx, r, stored([]File{a}), time.Minute, time.Millisecond)
	wantError(t, err, "cancel")
	if err != nil && strings.Contains(err.Error(), "after 1m0s") {
		t.Errorf("error %q reports a timeout for a cancelled run", err)
	}
}

// stored is what Sync reports when the primary holds each file as built.
func stored(files []File) []Object {
	var objs []Object
	for _, f := range files {
		objs = append(objs, Object{Key: "build/" + f.Name, ETag: f.MD5})
	}
	return objs
}

func TestWaitReplicatedKeptMap(t *testing.T) {
	r := newFakeStore()
	const keptETag = "0123456789abcdef0123456789abcdef"
	r.objects["build/a.vX.js.map"] = fakeObject{etag: keptETag}
	want := []Object{{Key: "build/a.vX.js.map", ETag: keptETag}}
	if err := WaitReplicated(context.Background(), r, want, time.Second, time.Millisecond); err != nil {
		t.Fatal(err)
	}
}
