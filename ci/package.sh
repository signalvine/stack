#!/bin/bash
set -x
set -e
set -o pipefail

rm -f *.deb

stack setup
stack build

get_version() {
  dpkg -s "$1" | grep Version: | grep -Eo ":\s+.*$" | grep -Eo "[^: ]+$"
}

stack_path="$(stack path | grep local-install-root | grep -Eo "/[/[a-zA-Z0-9_.-]+$")/bin/stack"

fpm -s dir -t deb -n stack --epoch 1 --maintainer roman@signalvine.com  \
  -v "$GO_PIPELINE_COUNTER.$(git rev-parse HEAD | grep -Eo '^[0-9a-fA-F]{7}')" \
  --description "Stack is a haskell build tool" -d "libc6 >= $(get_version libc6)" \
  -d "zlib1g >= $(get_version zlib1g)" -d "libgmp10 >= $(get_version libgmp10)" \
  -d "libgcc2 >= $(get_version libgcc1)" $stack_path=/usr/local/bin/
