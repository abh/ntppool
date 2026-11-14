package main

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"fmt"
)

type fakeObject struct {
	etag        string
	contentType string
}

// pendingObject shows up in objects on the at'th Head of its key.
type pendingObject struct {
	obj fakeObject
	at  int
}

// fakeStore is an in-memory Store with a write log and injectable errors.
type fakeStore struct {
	objects map[string]fakeObject
	writes  []string // "put <key>", "refresh <key>"
	heads   map[string]int

	headErr map[string]error
	putErr  map[string]error
	pending map[string]pendingObject
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		objects: map[string]fakeObject{},
		heads:   map[string]int{},
		headErr: map[string]error{},
		putErr:  map[string]error{},
		pending: map[string]pendingObject{},
	}
}

func (s *fakeStore) Head(_ context.Context, key string) (string, bool, error) {
	s.heads[key]++
	if p, ok := s.pending[key]; ok && s.heads[key] >= p.at {
		s.objects[key] = p.obj
		delete(s.pending, key)
	}
	if err := s.headErr[key]; err != nil {
		return "", false, err
	}
	obj, ok := s.objects[key]
	return obj.etag, ok, nil
}

func (s *fakeStore) Put(_ context.Context, key string, body []byte, contentType string) error {
	s.writes = append(s.writes, "put "+key)
	if err := s.putErr[key]; err != nil {
		return err
	}
	sum := md5.Sum(body)
	s.objects[key] = fakeObject{etag: hex.EncodeToString(sum[:]), contentType: contentType}
	return nil
}

func (s *fakeStore) Refresh(_ context.Context, key, contentType string) error {
	s.writes = append(s.writes, "refresh "+key)
	obj, ok := s.objects[key]
	if !ok {
		return fmt.Errorf("refresh %s: not found", key)
	}
	obj.contentType = contentType
	s.objects[key] = obj
	return nil
}

// testFile is newFile for a name the test knows is valid.
func testFile(name, body string) File {
	f, err := newFile(name, []byte(body))
	if err != nil {
		panic(err)
	}
	return f
}
