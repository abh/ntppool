package main

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// WaitReplicated polls replica until every object is there with the same
// ETag, or until timeout. want is Result.Stored from Sync. Keys already
// confirmed are not checked again. A Head error counts as "not yet"; the
// last one is in the timeout error.
func WaitReplicated(ctx context.Context, replica Store, want []Object, timeout, interval time.Duration) error {
	parent := ctx
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// key -> why it is still pending
	pending := make(map[string]string, len(want))
	for _, o := range want {
		pending[o.Key] = "not checked"
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		for _, o := range want {
			key := o.Key
			if _, ok := pending[key]; !ok {
				continue
			}
			etag, found, err := replica.Head(ctx, key)
			switch {
			case err != nil && ctx.Err() != nil:
				// The timeout cut this HEAD short; keep the reason from
				// the previous round.
			case err != nil:
				pending[key] = "head error: " + err.Error()
			case !found:
				pending[key] = "missing"
			case etag != o.ETag:
				pending[key] = fmt.Sprintf("ETag differs: replica %s, primary %s", etag, o.ETag)
			default:
				delete(pending, key)
			}
		}
		if len(pending) == 0 {
			return nil
		}

		select {
		case <-ctx.Done():
			if err := parent.Err(); err != nil {
				// Cancelled (SIGTERM, a cancelled CI step), not timed out.
				return fmt.Errorf("waiting for the replica, %d of %d files pending: %w",
					len(pending), len(want), err)
			}
			var lines []string
			for _, o := range want {
				if why, ok := pending[o.Key]; ok {
					lines = append(lines, o.Key+": "+why)
				}
			}
			return fmt.Errorf("%d of %d files not on the replica after %s:\n  %s",
				len(pending), len(want), timeout, strings.Join(lines, "\n  "))
		case <-ticker.C:
		}
	}
}
