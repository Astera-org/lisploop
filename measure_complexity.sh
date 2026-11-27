#!/usr/bin/bash
echo "v1"
cccc v1/*.lisp | jq '.summary | {cognitive, cyclomatic}'
echo "v2"
cccc v2/*.lisp | jq '.summary | {cognitive, cyclomatic}'
