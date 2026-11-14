package main

import (
	"context"
	"fmt"
	"strings"
)

// Store is the object store the build files go to.
type Store interface {
	// Head returns the object's ETag, without quotes and in lowercase.
	// found is false with a nil error only when the object does not exist;
	// any other failure, a 403 included, is an error.
	Head(ctx context.Context, key string) (etag string, found bool, err error)
	// Put writes the object in a single part, so its ETag is the MD5 of body.
	Put(ctx context.Context, key string, body []byte, contentType string) error
	// Refresh copies the object onto itself, which restarts its
	// Last-Modified (and its lifecycle clock) without changing the content.
	Refresh(ctx context.Context, key, contentType string) error
}

// Object is a key and the ETag the store holds for it.
type Object struct {
	Key  string
	ETag string
}

// Result lists the keys Sync wrote, and what the store holds afterwards.
type Result struct {
	Uploaded  []string
	Refreshed []string
	// KeptMaps are source maps whose stored content differs from this
	// build's; they were refreshed, not replaced (also in Refreshed).
	KeptMaps []string
	// Stored has every file's key and the ETag the store now holds for
	// it, in file order: the local MD5, or the stored ETag of a kept map.
	Stored []Object
}

// Sync uploads the files that are missing from s and refreshes the ones that
// are there with the same content. It checks every key before it writes
// anything, and fails without writing if any key holds different content or
// can't be checked.
//
// Source maps are the exception: the chunk hash in a .js.map name covers
// only the minified JS, so a comment-only source change gives the same name
// with a different map. The JS is the same bytes, so the stored map still
// fits it; Sync keeps and refreshes it instead of failing.
func Sync(ctx context.Context, s Store, prefix string, files []File) (Result, error) {
	var res Result
	exists := make([]bool, len(files))
	var conflicts []string
	for i, f := range files {
		key := prefix + f.Name
		etag, found, err := s.Head(ctx, key)
		if err != nil {
			return Result{}, fmt.Errorf("head %s: %w", key, err)
		}
		stored := f.MD5
		if found && etag != f.MD5 {
			if !strings.HasSuffix(f.Name, ".js.map") {
				conflicts = append(conflicts, fmt.Sprintf("%s: stored ETag %s, local MD5 %s", key, etag, f.MD5))
			} else {
				res.KeptMaps = append(res.KeptMaps, key)
				stored = etag
			}
		}
		exists[i] = found
		res.Stored = append(res.Stored, Object{Key: key, ETag: stored})
	}
	if len(conflicts) > 0 {
		return Result{}, fmt.Errorf("stored files differ from this build, nothing written:\n  %s",
			strings.Join(conflicts, "\n  "))
	}

	for i, f := range files {
		key := prefix + f.Name
		if exists[i] {
			if err := s.Refresh(ctx, key, f.ContentType); err != nil {
				return res, fmt.Errorf("refresh %s: %w", key, err)
			}
			res.Refreshed = append(res.Refreshed, key)
			continue
		}
		if err := s.Put(ctx, key, f.Body, f.ContentType); err != nil {
			return res, fmt.Errorf("put %s: %w", key, err)
		}
		res.Uploaded = append(res.Uploaded, key)
	}
	return res, nil
}
