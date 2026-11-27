#!/bin/sh
# Copy the trees this baseline needs into the work directory. The repository is not written to.
W="$(cd "$(dirname "$0")" && pwd)"
SRC="${REPO:-$(cd "$W/../.." && pwd)}"
X3_BASE_COMMIT="${X3_BASE_COMMIT:-65d1df2}"
mkdir -p "$W/kernel" "$W/logs" "$W/vr"
rm -rf "$W/kernel/v2"
git -C "$SRC" archive "$X3_BASE_COMMIT" v2 | tar -x -C "$W/kernel"
rsync -a --delete "$SRC/plan_v2c_audit/verify-review/" "$W/vr/orig/"
# a second, writable copy of the prototype run directory (its scripts write into logs/ beside themselves)
rsync -a --delete "$SRC/plan_v2c_audit/verify-review/" "$W/vr/run/"
rm -rf "$W/vr/run/logs"
mkdir -p "$W/vr/run/logs"
( cd "$SRC" && git rev-parse HEAD && git status --short ) > "$W/logs/repo-state-before.txt" 2>&1
sbcl --version > "$W/logs/sbcl-version.txt" 2>&1
echo "copied; repo state in logs/repo-state-before.txt"
