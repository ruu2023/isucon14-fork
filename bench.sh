#!/bin/bash
set -e
export PATH=$PATH:$HOME/go-sdk/bin
cd "$(dirname "$0")/bench"
go run . run --target http://localhost:8080 -t 60 --payment-url http://host.docker.internal:12345 "$@"
