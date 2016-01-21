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

get_dependencies() {
  # Gets a list of all of the unique libraries that contain a library that this binary links against
  while read line; do
    echo -n "-d \"$line >= $(get_version $line)\" "
  done < <(ldd $1 | grep -Eo "/[a-zA-Z0-9/_.-]+" | xargs -L 1 dpkg -S | grep -Eo "^[^ :]+" | sort | uniq)
}

stack_path="$(stack path | grep local-install-root | grep -Eo "/[/[a-zA-Z0-9_.-]+$")/bin/stack"

eval "fpm -s dir -t deb -n stack --epoch 1 --maintainer roman@signalvine.com -v \"$GO_PIPELINE_COUNTER.$(git rev-parse HEAD | grep -Eo '^[0-9a-fA-F]{7}')\" --description \"Stack is a haskell build tool\" $(get_dependencies $stack_path) $stack_path=/usr/local/bin/"
