// Command static-upload copies the hash-named client build files to the
// ntppool-static bucket, so HTML from any recent build still finds its JS
// and CSS. It uploads missing files, refreshes identical ones, fails on any
// other difference, and waits until the second zone has every file.
//
// Design: ntppool-plans/ntppool/docs/superpowers/specs/2026-11-15-static-build-asset-store-design.md
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	dir := flag.String("dir", "", "build directory to upload (required)")
	bucket := flag.String("bucket", "ntppool-static", "bucket name")
	prefix := flag.String("prefix", "build/", "key prefix")
	endpoint := flag.String("endpoint", "https://c3.hkga.ntp.dev/", "endpoint to write to")
	replicaEndpoint := flag.String("replica-endpoint", "https://c3.dala.ntp.dev/", "endpoint of the zone to wait for")
	timeout := flag.Duration("timeout", 10*time.Minute, "how long to wait for the replica")
	interval := flag.Duration("interval", 5*time.Second, "how often to check the replica")
	flag.Parse()

	if *dir == "" {
		return fmt.Errorf("-dir is required")
	}
	if flag.NArg() > 0 {
		return fmt.Errorf("unexpected arguments: %v", flag.Args())
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	files, err := SelectFiles(*dir)
	if err != nil {
		return err
	}
	log.Printf("selected %d files from %s", len(files), *dir)

	primary, err := newS3Store(*endpoint, *bucket)
	if err != nil {
		return err
	}
	replica, err := newS3Store(*replicaEndpoint, *bucket)
	if err != nil {
		return err
	}

	res, err := Sync(ctx, primary, *prefix, files)
	for _, key := range res.Uploaded {
		log.Printf("uploaded %s", key)
	}
	if err != nil {
		return err
	}
	for _, key := range res.KeptMaps {
		log.Printf("warning: kept the stored %s, which differs from this build's (same JS, different source map)", key)
	}
	log.Printf("%s: %d uploaded, %d refreshed", *endpoint, len(res.Uploaded), len(res.Refreshed))

	if err := WaitReplicated(ctx, replica, res.Stored, *timeout, *interval); err != nil {
		return err
	}
	log.Printf("%s: all %d files replicated", *replicaEndpoint, len(files))
	return nil
}
