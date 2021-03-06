#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2046
set -e
set -x

# %<---[setup]----------------------------------------------------------------

WORKDIR=${WORKDIR:-$HOME}
cd "$WORKDIR" || exit

REVISION=$(curl -sL https://build.fuzzing.mozilla.org/builds/coverage-revision.txt)
export REVISION

# Setup required coverage environment variables.
export COVERAGE=1
export GCOV_PREFIX_STRIP=6
export GCOV_PREFIX="$WORKDIR/firefox"

# Our default target is Firefox, but we support targetting the JS engine instead.
# In either case, we check if the target is already mounted into the container.
# For coverage, we also are pinned to a given revision and we need to fetch coverage builds.
TARGET_BIN="firefox/firefox"
export JS=${JS:-0}
if [ "$JS" = 1 ]
then
  if [[ ! -d "$HOME/js" ]]
  then
    fuzzfetch --build "$REVISION" --asan --coverage --fuzzing --tests gtest -n js -o "$WORKDIR" --target js
  fi
  chmod -R 755 js
  TARGET_BIN="js/fuzz-tests"
  export GCOV_PREFIX="$WORKDIR/js"
elif [[ ! -d "$HOME/firefox" ]]
then
  fuzzfetch --build "$REVISION" --asan --coverage --fuzzing --tests gtest -n firefox -o "$WORKDIR"
  chmod -R 755 firefox
fi

# %<---[fuzzer]---------------------------------------------------------------

timeout -s 2 -k $((COVRUNTIME + 60)) "$COVRUNTIME" ./libfuzzer.sh || :

# %<---[coverage]-------------------------------------------------------------

# Collect coverage count data.
RUST_BACKTRACE=1 grcov "$GCOV_PREFIX" \
    -t coveralls+ \
    --commit-sha "$REVISION" \
    --token NONE \
    -p $(rg -Nor '$1' "pathprefix = (.*)" "$WORKDIR/${TARGET_BIN}.fuzzmanagerconf") \
    > "$WORKDIR/coverage.json"

# Submit coverage data.
python -m CovReporter.CovReporter \
    --repository mozilla-central \
    --description "libFuzzer ($FUZZER,rt=$COVRUNTIME)" \
    --tool "libFuzzer-$FUZZER" \
    --submit "$WORKDIR/coverage.json"
