#!/usr/bin/env bash
# set -x

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <harness_path> <project_name>"
    exit 1
fi

export AFL_AUTORESUME=1
export AFL_FUZZER_LOOPCOUNT=1000
export AFL_PIZZA_MODE=-1
export AFL_BASE=$SRC/aflplusplus/

export HWASAN_OPTIONS=verbosity=0:detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1
unset HWASAN_SYMBOLIZER_PATH

HARNESS_FULLPATH=$(realpath $1)
PROJECT_NAME=$2
INSTANCES=${INSTANCES:-1}
PRODUCE_OUTPUT=${PRODUCE_OUTPUT:-1}
PINNED_CORE=${PINNED_CORE:-0} # only meaningful when INSTANCES=1, otherwise cores are automatically assigned from the E_CORE_LIST
# be smart and find the first core starting from 0 where NO FUZZER PROCESS is pinned
if [ $PINNED_CORE -eq 0 ]; then
    echo set PINNED_CORE...
    exit 1
fi

echo "Using pinned core: $PINNED_CORE"
WITH_DICTIONARY=${WITH_DICTIONARY:-""}

echo "Using harness: $HARNESS_FULLPATH"
echo "Using project name: $PROJECT_NAME"
echo "Using instances: $INSTANCES"
echo "PRODUCE OUTPUT: $PRODUCE_OUTPUT"

# assert the file exists
if [ ! -f "$HARNESS_FULLPATH" ]; then
    echo "Harness file $HARNESS_FULLPATH does not exist. Please provide a valid path to the harness."
    exit 1
fi

HARNESS_NAME=$(basename "$HARNESS_FULLPATH")

if [ ! -d "$OUT" ]; then
    echo "Output directory $OUT does not exist. Please set the OUT environment variable."
    exit 1
fi
# find pre-existing directory where the previous campaign was running, restart the fuzzers from there

SECONDS=$((72 * 3600)) # 3 day runs
FUZZ_TOUT="${FUZZ_TOUT:-100}"
# if the harness is fuzz_route in project gpac, set all TOUTs to 250
if [[ "$HARNESS_NAME" == *"fuzz_route"* ]] && [[ "$PROJECT_NAME" == *"gpac"* ]]; then
    FUZZ_TOUT=250
fi


core=$PINNED_CORE
if [ ! -d "/fuzzing-campaign" ]; then
    exit 1
fi
outdir="/fuzzing-campaign/${HARNESS_NAME}_0" # store campaign on host
if [ -d "$outdir" ]; then
    echo "Found existing campaign directory $outdir. Resuming fuzzing from there."
else
    echo "No existing campaign directory found. Starting a new fuzzing campaign."
    mkdir -p "$outdir"
fi

instance_corpusdir="$OUT/${HARNESS_NAME}_0"
rm -rf "$outdir" 2>/dev/null || true
rm -rf "$instance_corpusdir" 2>/dev/null || true
cp -r $CORPUS_DIR "$instance_corpusdir" # this might be empty
echo "launching instance $i on core $core"
OUT_REDIR=""
RANDOM_NUMBER=$RANDOM
DICT=""
if [ ! -z "$WITH_DICTIONARY" ]; then
    DICT=" -x ${WITH_DICTIONARY} "
fi
export AFL_AUTORESUME=1
CMD="AFL_SEED=$RANDOM $AFL_BASE/afl-fuzz -i \"$instance_corpusdir\" -o \"$outdir\" -b$core -V $SECONDS $DICT -t $FUZZ_TOUT+ -- $HARNESS_FULLPATH @@"
if [ "$PRODUCE_OUTPUT" -eq 0 ]; then
    CMD="$CMD > /dev/null 2>&1"
fi
eval "$CMD &"

wait $!
echo DONE!
echo CONTENT OF OUT DIRECTORIES for CRASHES :k

ls -l $OUT/$HARNESS_NAME*/crashes

