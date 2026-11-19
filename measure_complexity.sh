#!/usr/bin/bash

cccc *.lisp | jq '.summary | {cognitive, cyclomatic}'
