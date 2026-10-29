#!/bin/sh
set -eu
GOODGOOD_PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$GOODGOOD_PROJECT_ROOT/flutterw" "$@"
