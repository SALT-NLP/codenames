#!/bin/bash

set -ex

go install github.com/jbowens/codenamesgreen/cmd/greenapid
npx parcel build src/index.html
cp -R src/images dist/
cp src/robots.txt dist/
