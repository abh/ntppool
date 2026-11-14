package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

// s3Store is a Store on one bucket at one RGW endpoint.
type s3Store struct {
	client *s3.Client
	bucket string
}

// newS3Store connects to bucket at endpoint with the credentials in
// AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY. It doesn't fall back to other
// credential sources.
func newS3Store(endpoint, bucket string) (*s3Store, error) {
	key, secret := os.Getenv("AWS_ACCESS_KEY_ID"), os.Getenv("AWS_SECRET_ACCESS_KEY")
	if key == "" || secret == "" {
		return nil, errors.New("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set")
	}
	client := s3.New(s3.Options{
		AppID:        "static-upload",
		BaseEndpoint: aws.String(endpoint),
		UsePathStyle: true,
		Region:       "c3",
		Credentials:  credentials.NewStaticCredentialsProvider(key, secret, ""),
		// No checksum trailers: PutObject sends a plain body, so the ETag
		// stays the MD5 of the content.
		RequestChecksumCalculation: aws.RequestChecksumCalculationWhenRequired,
		ResponseChecksumValidation: aws.ResponseChecksumValidationWhenRequired,
	})
	return &s3Store{client: client, bucket: bucket}, nil
}

func (s *s3Store) Head(ctx context.Context, key string) (string, bool, error) {
	out, err := s.client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		if isNotFound(err) {
			return "", false, nil
		}
		return "", false, err
	}
	if out.ETag == nil {
		return "", false, errors.New("no ETag in the response")
	}
	return strings.ToLower(strings.Trim(*out.ETag, `"`)), true, nil
}

// isNotFound is true only for a real 404. A 403 (or anything else) is not
// "missing": reading it that way would PUT over an existing key.
func isNotFound(err error) bool {
	var re *smithyhttp.ResponseError
	return errors.As(err, &re) && re.HTTPStatusCode() == http.StatusNotFound
}

func (s *s3Store) Put(ctx context.Context, key string, body []byte, contentType string) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          bytes.NewReader(body),
		ContentLength: aws.Int64(int64(len(body))),
		ContentType:   aws.String(contentType),
	})
	return err
}

func (s *s3Store) Refresh(ctx context.Context, key, contentType string) error {
	_, err := s.client.CopyObject(ctx, &s3.CopyObjectInput{
		Bucket:            aws.String(s.bucket),
		Key:               aws.String(key),
		CopySource:        aws.String(copySource(s.bucket, key)),
		MetadataDirective: types.MetadataDirectiveReplace,
		ContentType:       aws.String(contentType),
	})
	return err
}

// copySource is "bucket/key" with every byte of the key outside the RFC 3986
// unreserved set percent-encoded, except the "/" between segments. That
// sends logo-2019@x2.v<hash>.png as logo-2019%40x2.v<hash>.png;
// url.PathEscape would leave the "@" as it is.
func copySource(bucket, key string) string {
	var b strings.Builder
	b.WriteString(bucket)
	b.WriteByte('/')
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c == '/', c == '-', c == '_', c == '.', c == '~',
			'A' <= c && c <= 'Z', 'a' <= c && c <= 'z', '0' <= c && c <= '9':
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}
