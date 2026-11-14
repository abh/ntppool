package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// s3Request is what the fake RGW saw.
type s3Request struct {
	method, path, copySource, trailer, contentType, body string
}

func testS3Store(t *testing.T, handler func(w http.ResponseWriter, r *http.Request)) (*s3Store, *[]s3Request) {
	t.Helper()
	var seen []s3Request
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		seen = append(seen, s3Request{
			method:      r.Method,
			path:        r.URL.EscapedPath(),
			copySource:  r.Header.Get("X-Amz-Copy-Source"),
			trailer:     r.Header.Get("X-Amz-Trailer"),
			contentType: r.Header.Get("Content-Type"),
			body:        string(body),
		})
		handler(w, r)
	}))
	t.Cleanup(srv.Close)
	t.Setenv("AWS_ACCESS_KEY_ID", "test-key")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "test-secret")
	s, err := newS3Store(srv.URL, "ntppool-static")
	if err != nil {
		t.Fatal(err)
	}
	return s, &seen
}

func TestS3HeadNotFound(t *testing.T) {
	s, _ := testS3Store(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})
	_, found, err := s.Head(context.Background(), "build/a.vX.js")
	if err != nil || found {
		t.Fatalf("Head = found %v, err %v; want not found, nil", found, err)
	}
}

func TestS3HeadForbiddenIsError(t *testing.T) {
	s, _ := testS3Store(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	})
	_, found, err := s.Head(context.Background(), "build/a.vX.js")
	if err == nil {
		t.Fatalf("Head on a 403 = found %v, nil error; want an error", found)
	}
}

func TestS3HeadETag(t *testing.T) {
	s, seen := testS3Store(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("ETag", `"0CC175B9C0F1B6A831C399E269772661"`)
		w.WriteHeader(http.StatusOK)
	})
	etag, found, err := s.Head(context.Background(), "build/a.vX.js")
	if err != nil || !found {
		t.Fatalf("Head = found %v, err %v", found, err)
	}
	if etag != "0cc175b9c0f1b6a831c399e269772661" {
		t.Fatalf("etag = %q", etag)
	}
	if got := (*seen)[0].path; got != "/ntppool-static/build/a.vX.js" {
		t.Fatalf("path = %q, want path-style", got)
	}
}

func TestS3PutPlainBody(t *testing.T) {
	s, seen := testS3Store(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	if err := s.Put(context.Background(), "build/a.vX.js", []byte("a"), "text/javascript; charset=utf-8"); err != nil {
		t.Fatal(err)
	}
	req := (*seen)[0]
	if req.method != http.MethodPut || req.body != "a" {
		t.Fatalf("request = %+v, want a PUT with the plain body", req)
	}
	if req.trailer != "" {
		t.Fatalf("X-Amz-Trailer = %q, want no checksum trailer", req.trailer)
	}
	if req.contentType != "text/javascript; charset=utf-8" {
		t.Fatalf("Content-Type = %q", req.contentType)
	}
}

func TestS3RefreshCopiesOntoItself(t *testing.T) {
	s, seen := testS3Store(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, `<CopyObjectResult><ETag>"x"</ETag></CopyObjectResult>`)
	})
	if err := s.Refresh(context.Background(), "build/logo-2019@x2.vGh3.png", "image/png"); err != nil {
		t.Fatal(err)
	}
	req := (*seen)[0]
	if req.copySource != "ntppool-static/build/logo-2019%40x2.vGh3.png" {
		t.Fatalf("X-Amz-Copy-Source = %q", req.copySource)
	}
	if req.contentType != "image/png" {
		t.Fatalf("Content-Type = %q", req.contentType)
	}
}

func TestS3MissingCredentials(t *testing.T) {
	t.Setenv("AWS_ACCESS_KEY_ID", "")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "")
	if _, err := newS3Store("https://c3.hkga.ntp.dev/", "ntppool-static"); err == nil {
		t.Fatal("newS3Store without credentials: want an error")
	}
}
