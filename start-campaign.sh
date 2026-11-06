#!/usr/bin/env bash
# set -x

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <harness_path> <project_name>"
    exit 1
fi
RESUME_CAMPAIGN=${RESUME_CAMPAIGN:-"yesbaby"}
if [ ! -z "$RESUME_CAMPAIGN" ]; then
    export AFL_AUTORESUME=1
    SKIP_FILTERING=1
    echo "Resuming campaign for harness: $1, project: $2"
fi

export AFL_FUZZER_LOOPCOUNT=2000 # TODO modify AFL and FSan to implement effective fuzzing in recovery mode
# export AFL_IGNORE_SEED_PROBLEMS=1
export AFL_PIZZA_MODE=-1
export AFL_CRASH_EXITCODE=99
export AFL_NO_UI=1
export AFL_TESTCACHE_SIZE=${AFL_TESTCACHE_SIZE:-500} # MB
export AFL_BASE=$SRC/aflplusplus/
# just register the crash
export HWASAN_OPTIONS=${HWASAN_OPTIONS/"recover_report=summary"/"recover_report=quiet"}
unset HWASAN_SYMBOLIZER_PATH

HARNESS_FULLPATH=$(realpath $1)
PROJECT_NAME=$2
PRODUCE_OUTPUT=${PRODUCE_OUTPUT:-1}
PINNED_CORE=${PINNED_CORE:-0}
FILTER_JOBS=${FILTER_JOBS:-10}
# be smart and find the first core starting from 0 where NO FUZZER PROCESS is pinned
echo "Using pinned core: $PINNED_CORE"
sleep 2
WITH_DICTIONARY=${WITH_DICTIONARY:-""}

echo "Using harness: $HARNESS_FULLPATH"
echo "Using project name: $PROJECT_NAME"
echo "PRODUCE OUTPUT: $PRODUCE_OUTPUT"
sleep 1

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
if [ ! -d "/fuzzing-campaign" ]; then
    echo "/fuzzing-campaign does not exist."
    exit 1
fi
pip install tqdm

# find a dictionary: WITH_DICTIONARY, then $OUT/<harness>.dict, then <harness>.options
if [ -z "$WITH_DICTIONARY" ]; then
    if [ -f "$OUT/${HARNESS_NAME}.dict" ]; then
        WITH_DICTIONARY="$OUT/${HARNESS_NAME}.dict"
    elif [ -f "$OUT/${HARNESS_NAME}.options" ]; then
        DICT_NAME=$(sed -n 's/^[[:space:]]*dict[a-z]*[[:space:]]*=[[:space:]]*//p' "$OUT/${HARNESS_NAME}.options" | head -n 1 | tr -d '[:space:]')
        if [ -n "$DICT_NAME" ] && [ -f "$OUT/$DICT_NAME" ]; then
            WITH_DICTIONARY="$OUT/$DICT_NAME"
        fi
    fi
fi
echo "Using dictionary: ${WITH_DICTIONARY:-none}"

# get the corpus: reuse the pinned copy, or pin it on the first run
PIN_DIR="/fuzzing-campaign/corpus-pins"
PINNED_CORPUS="$PIN_DIR/${PROJECT_NAME}_${HARNESS_NAME}.zip"
PINNED_HASH="$PINNED_CORPUS.sha256"
mkdir -p "$PIN_DIR" || true

if [ -f "$PINNED_CORPUS" ]; then
    echo "[+] USING PINNED CORPUS: $PINNED_CORPUS"
else
    CORPUS_TMP_FILE="/tmp/corpus.${HARNESS_NAME}.zip"
    wget -O $CORPUS_TMP_FILE "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${PROJECT_NAME}_${HARNESS_NAME}/public.zip" || wget -O $CORPUS_TMP_FILE "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${HARNESS_NAME}/public.zip"

    if [ -f "$CORPUS_TMP_FILE" -a -s "$CORPUS_TMP_FILE" ]; then
        echo "[+] CORPUS DOWNLOADED SUCCESSFULLY: $CORPUS_TMP_FILE"
        stat $CORPUS_TMP_FILE
        mv "$CORPUS_TMP_FILE" "$PINNED_CORPUS"
    else
        rm -f "$CORPUS_TMP_FILE" 2>/dev/null || true
        # check if something like HARNESS_NAME*zip exists in /out, if so, use that as corpus
        LOCAL_CORPUS=$(ls /out/${HARNESS_NAME}*.zip 2>/dev/null | head -n 1)
        if [ -f "$LOCAL_CORPUS" ]; then
            echo "[+] CORPUS FOUND LOCALLY: $LOCAL_CORPUS"
            cp "$LOCAL_CORPUS" "$PINNED_CORPUS"
        else
            exit 1
        fi
    fi
    sha256sum "$PINNED_CORPUS" > "$PINNED_HASH"
    echo "[+] CORPUS PINNED: $PINNED_CORPUS"
fi

if ! sha256sum -c "$PINNED_HASH"; then
    echo "[!] PINNED CORPUS DOES NOT MATCH $PINNED_HASH"
    exit 1
fi

# unpack into an empty directory, so the corpus is exactly what was pinned
CORPUS_DIR="$OUT/corpus-${HARNESS_NAME}"
rm -rf "$CORPUS_DIR" 2>/dev/null || true
unzip -o "$PINNED_CORPUS" -d "$CORPUS_DIR" 2>&1 >/dev/null 2>&1
echo "[+] CORPUS UNPACKED! SIZE IS: $(ls $CORPUS_DIR | wc -l)"
sleep 1

#create filter dir
FILTERED_DIR=/crashes-$HARNESS_NAME
rm -rf $FILTERED_DIR 2>/dev/null || true
mkdir -p $FILTERED_DIR 2>/dev/null || true

filter_input() {
    local input=$1
    timeout -s TERM 2s "$HARNESS_FULLPATH" "$input" >/dev/null 2>&1
    local rc=$?

    if [ $rc -ne 0 ]; then
        echo "[!] Input $input caused a timeout or crash (exit code: $rc), MOVING IT."
        mv "$input" "$FILTERED_DIR"/$(basename "$input").$rc
    fi
    return 0
}

if [ -z "$SKIP_FILTERING" ]
then
    export HARNESS_FULLPATH FILTERED_DIR
    export -f filter_input
    echo "[+] FILTERING $(ls "$CORPUS_DIR" | wc -l) INPUTS WITH $FILTER_JOBS JOBS"
    find "$CORPUS_DIR" -maxdepth 1 -type f -print0 | xargs -0 -r -P "$FILTER_JOBS" -n 1 bash -c 'filter_input "$1"' _
fi
set -x
echo "[+] CORPUS FILTERED:"
echo "[+] FOUND CRASHES/HANGS IN CORPUS: $(ls $FILTERED_DIR | wc -l) files"
sleep 1
CMIN_TOUT="${CMIN_TOUT:-100}"
# if the harness is fuzz_route, set all TOUTs to 250
if [[ "$HARNESS_NAME" == *"fuzz_route"* ]]; then
    CMIN_TOUT=250
fi
# if any corpus, minimize
if [ "$(ls -A $CORPUS_DIR)" -a -z "$RESUME_CAMPAIGN" ]; then
    echo "[+] CORPUS NOT EMPTY, PROCEEDING TO MINIMIZATION."
    MINIMIZED_DIR="$OUT/corpus_cmin-${HARNESS_NAME}"
    rm -rf "$MINIMIZED_DIR" 2>/dev/null || true
    echo "[+] MINIMIZING CORPUS WITH AFL-CMIN: CURRENT SIZE IS: $(ls $CORPUS_DIR | wc -l)"
    $AFL_BASE/afl-cmin -t $CMIN_TOUT -i "$CORPUS_DIR" -o "$MINIMIZED_DIR" -m none -T 24 -- $HARNESS_FULLPATH @@
    NEW_SIZE=$(ls $MINIMIZED_DIR/ | wc -l)
    if [ $NEW_SIZE -eq 0 ]; then
        echo "[!] MINIMIZATION FAILED, USING ORIGINAL CORPUS."
        mv $CORPUS_DIR "$MINIMIZED_DIR" 2>/dev/null || true
        CORPUS_DIR="$MINIMIZED_DIR"
    else
        echo "[+] MINIMIZATION SUCCEEDED, NEW SIZE IS: $NEW_SIZE"
        CORPUS_DIR="$MINIMIZED_DIR"
    fi
    sleep 1
else
    echo "[+] CORPUS IS EMPTY, SKIPPING MINIMIZATION."
fi

$AFL_BASE/afl-system-config

SECONDS=$((72 * 3600)) # 3 day runs
FUZZ_TOUT="${FUZZ_TOUT:-100}"
# if the harness is fuzz_route in project gpac, set all TOUTs to 250
if [[ "$HARNESS_NAME" == *"fuzz_route"* ]] && [[ "$PROJECT_NAME" == *"gpac"* ]]; then
    FUZZ_TOUT=250
fi

outdir="/fuzzing-campaign/${HARNESS_NAME}_0" # store campaign on host
instance_corpusdir="$OUT/${HARNESS_NAME}_0"
if [ -z "$RESUME_CAMPAIGN" ]; then
    rm -rf "$outdir" 2>/dev/null || true # run with AUTORESUME
    rm -rf "$instance_corpusdir" 2>/dev/null || true
    cp -r $CORPUS_DIR "$instance_corpusdir" # this might be empty
fi

echo "launching fuzzer on core $PINNED_CORE"

DICT=""
if [ ! -z "$WITH_DICTIONARY" ]; then
    DICT=" -x ${WITH_DICTIONARY} "
fi
CMD="AFL_SEED=$RANDOM $AFL_BASE/afl-fuzz -i \"$instance_corpusdir\" -o \"$outdir\" -b$PINNED_CORE -V $SECONDS $DICT -t $FUZZ_TOUT+ -- $HARNESS_FULLPATH @@"
if [ "$PRODUCE_OUTPUT" -eq 0 ]; then
    CMD="$CMD > /dev/null 2>&1"
fi

eval "$CMD"
echo DONE!
echo CONTENT OF OUT DIRECTORIES for CRASHES :k

ls -l $OUT/$HARNESS_NAME*/crashes