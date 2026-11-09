#!/usr/bin/env bash
# Starts (or resumes) an AFL++ campaign on an FSan harness.
# set -x

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <harness_path> <project_name>"
    exit 1
fi

export AFL_FUZZER_LOOPCOUNT=2000 # arbitrary
# export AFL_IGNORE_SEED_PROBLEMS=1 # do not
export AFL_PIZZA_MODE=-1
export AFL_CRASH_EXITCODE=99 # fixed in runtime
# A seed that exits 99 in the dry run (the first with a new FSan violation) is
# saved to default/crashes, where classify_crashes.py looks.
export AFL_CRASHING_SEEDS_AS_NEW_CRASH=1
# FSan already reports each violation once (fsan_dedup_violations): save every
# such crash (exit 99), also one on the edges of an earlier crash; segfaults
# and aborts keep AFL++'s deduplication (needs the AFL++ with
# AFL_KEEP_ALL_CRASHES).
export AFL_KEEP_ALL_CRASHES=1
export AFL_NO_UI=1
export AFL_TESTCACHE_SIZE=${AFL_TESTCACHE_SIZE:-500}
export AFL_BASE=$SRC/aflplusplus/
# fsan_dedup_violations: only an input with a violation that no earlier input
# had exits 99, so the fuzzer goes through the false positives it already saw.
# The AFL++ tools also set LSAN_OPTIONS, which HWASan reads after these: its
# handle_segv=0, abort_on_error=1, symbolize=0 and allocator_may_return_null=1
# win, so segfaults and aborts reach AFL++ as signals, apart from exit 99.
export HWASAN_OPTIONS=halt_on_error=0:recover_report=quiet:fsan_dedup_violations=1:dedup_stack_depth=3:exitcode=99:abort_on_error=1:symbolize=0:detect_leaks=0:malloc_context_size=0:allocator_may_return_null=1

unset HWASAN_SYMBOLIZER_PATH

HARNESS_FULLPATH=$(realpath "$1")
PROJECT_NAME=$2

PINNED_CORE=${PINNED_CORE:-0}
FILTER_JOBS=${FILTER_JOBS:-10}
# AFL++ reads at most MAX_FILE (1 MB) of a seed.
MAX_INPUT_SIZE=${MAX_INPUT_SIZE:-1048576}

echo "Using pinned core: $PINNED_CORE"
echo "Using harness: $HARNESS_FULLPATH"
echo "Using project name: $PROJECT_NAME"

if [ ! -f "$HARNESS_FULLPATH" ]; then
    echo "Harness file $HARNESS_FULLPATH does not exist. Please provide a valid path to the harness."
    exit 1
fi
if [ ! -d "$OUT" ]; then
    echo "Output directory $OUT does not exist. Please set the OUT environment variable."
    exit 1
fi
if [ ! -d "/fuzzing-campaign" ]; then
    echo "/fuzzing-campaign does not exist."
    exit 1
fi
HARNESS_NAME=$(basename "$HARNESS_FULLPATH")
OUTDIR="/fuzzing-campaign/${HARNESS_NAME}_0" # store campaign on host

WITH_DICTIONARY=${WITH_DICTIONARY:-""}
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

FUZZ_TOUT="${FUZZ_TOUT:-100}"
# ADJs. for trashy harnesses
# if [[ "$HARNESS_NAME" == *"fuzz_route"* ]] && [[ "$PROJECT_NAME" == *"gpac"* ]]; then
#     FUZZ_TOUT=250
# fi
# afl-cmin drops the inputs that time out, so it uses the fuzzer's timeout: it
# keeps what the fuzzer can run.
CMIN_TOUT="${CMIN_TOUT:-$FUZZ_TOUT}"

# A new campaign gets its seeds from the pinned OSS-Fuzz corpus
# (KICKSTART_WITH_EXT_SEEDS), else from the harness's seed corpus in $OUT, else
# from a single dummy input. They are unpacked, cut to MAX_INPUT_SIZE, then
# minimized by coverage alone: crashes and violations are the fuzzer's business.
RESUME_CAMPAIGN=${RESUME_CAMPAIGN:-""}
SKIP_MINIMIZATION=${SKIP_MINIMIZATION:-""}
RECORD_SEEDS=${RECORD_SEEDS:-"yesbaby"}
KICKSTART_WITH_EXT_SEEDS=${KICKSTART_WITH_EXT_SEEDS:-""}
if [ -d "$OUTDIR" ] && [ -n "$RESUME_CAMPAIGN" ]; then
    echo "[+] OUT DIR EXISTS, RESUMING CAMPAIGN."
    export AFL_AUTORESUME=1
    RESUME_CAMPAIGN=1
    echo "Resuming campaign for harness: $1, project: $2"
fi

CORPUS_DIR="$OUT/corpus-${HARNESS_NAME}"  # the corpus, unpacked
SEED_DIR="$OUT/${HARNESS_NAME}_0"         # the corpus, minimized: what afl-fuzz starts from
FILTERED_DIR="/crashes-$HARNESS_NAME"     # what seeds trigger, with their exit code as suffix

# RECORD_SEEDS: copies an input that the harness does not run cleanly to
# $FILTERED_DIR, with the exit code as suffix (99: an FSan violation, 124: a
# timeout), for classify_crashes.py. It does not change the corpus.
record_input() {
    local input=$1 rc
    timeout -s TERM 2s "$HARNESS_FULLPATH" "$input" >/dev/null 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        cp "$input" "$FILTERED_DIR/$(basename "$input").$rc"
    fi
    return 0
}

# Keeps the inputs that add coverage. The harness exits 99 after an input with
# a new FSan violation: without AFL_CRASH_EXITCODE that is a normal run, whose
# coverage counts, so violations and false positives stay in the corpus. Real
# crashes go to $FILTERED_DIR/cmin, not into the corpus; timeouts are dropped.
do_minimization() {
    local corpus_dir=$1 minimized_dir=$2 new_size
    echo "[+] MINIMIZING CORPUS WITH AFL-CMIN: CURRENT SIZE IS: $(ls "$corpus_dir" | wc -l)"
    rm -rf "$minimized_dir"
    env -u AFL_CRASH_EXITCODE "$AFL_BASE/afl-cmin" -t "$CMIN_TOUT" -i "$corpus_dir" -o "$minimized_dir" -m none -T "$FILTER_JOBS" --crash-dir "$FILTERED_DIR/cmin" -- "$HARNESS_FULLPATH" @@
    new_size=$(ls "$minimized_dir" 2>/dev/null | wc -l)
    if [ "$new_size" -eq 0 ]; then
        echo "[!] MINIMIZATION FAILED, USING THE WHOLE CORPUS."
        mkdir -p "$minimized_dir"
        cp -a "$corpus_dir"/. "$minimized_dir"/
        return 1
    fi
    echo "[+] MINIMIZATION SUCCEEDED, NEW SIZE IS: $new_size"
    return 0
}

if [ -n "$RESUME_CAMPAIGN" ]; then
    # AFL_AUTORESUME resumes from the queue in $OUTDIR, whatever -i says.
    INDIR="$OUTDIR"
else
    SEED_ZIP=""
    if [ -n "$KICKSTART_WITH_EXT_SEEDS" ]; then
        # do the download/find it locally
        PIN_DIR="/fuzzing-campaign/corpus-pins"
        mkdir -p "$PIN_DIR" || true
        PINNED_CORPUS="$PIN_DIR/${PROJECT_NAME}_${HARNESS_NAME}.zip"
        PINNED_HASH="$PINNED_CORPUS.sha256"
        if [ -f "$PINNED_CORPUS" ]; then
            echo "[+] USING PINNED CORPUS: $PINNED_CORPUS"
        else
            CORPUS_TMP_FILE="/tmp/corpus.${HARNESS_NAME}.zip"
            wget -O "$CORPUS_TMP_FILE" "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${PROJECT_NAME}_${HARNESS_NAME}/public.zip" || wget -O "$CORPUS_TMP_FILE" "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${HARNESS_NAME}/public.zip"

            if [ -f "$CORPUS_TMP_FILE" ] && [ -s "$CORPUS_TMP_FILE" ]; then
                echo "[+] CORPUS DOWNLOADED SUCCESSFULLY: $CORPUS_TMP_FILE"
                stat "$CORPUS_TMP_FILE"
                mv "$CORPUS_TMP_FILE" "$PINNED_CORPUS"
            else
                rm -f "$CORPUS_TMP_FILE" 2>/dev/null || true
                # check if something like HARNESS_NAME*zip exists in /out, if so, use that as corpus
                LOCAL_CORPUS=$(ls /out/"${HARNESS_NAME}"*.zip 2>/dev/null | head -n 1)
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
        SEED_ZIP="$PINNED_CORPUS"
    elif [ -f "$OUT/${HARNESS_NAME}_seed_corpus.zip" ]; then
        SEED_ZIP="$OUT/${HARNESS_NAME}_seed_corpus.zip"
        echo "[+] USING THE HARNESS'S SEED CORPUS: $SEED_ZIP"
    fi

    # unpack into an empty directory, so the corpus is exactly what was pinned
    rm -rf "$CORPUS_DIR" 2>/dev/null || true
    mkdir -p "$CORPUS_DIR"
    if [ -n "$SEED_ZIP" ]; then
        unzip -qo "$SEED_ZIP" -d "$CORPUS_DIR"
    fi
    find "$CORPUS_DIR" -maxdepth 1 -type f -size +"${MAX_INPUT_SIZE}"c -printf "[!] Input %p is too large (%s bytes), deleting it.\n" -delete
    if [ -z "$(ls -A "$CORPUS_DIR")" ]; then
        echo "[!] NO SEEDS, STARTING FROM A DUMMY INPUT."
        printf 'a' > "$CORPUS_DIR/dummy"
    fi
    echo "[+] CORPUS UNPACKED! SIZE IS: $(ls "$CORPUS_DIR" | wc -l)"

    rm -rf "$FILTERED_DIR" 2>/dev/null || true
    mkdir -p "$FILTERED_DIR" 2>/dev/null || true
    if [ -n "$RECORD_SEEDS" ]; then
        export -f record_input
        export HARNESS_FULLPATH FILTERED_DIR
        echo "[+] RECORDING WHAT $(ls "$CORPUS_DIR" | wc -l) INPUTS TRIGGER WITH $FILTER_JOBS JOBS"
        find "$CORPUS_DIR" -maxdepth 1 -type f -print0 | xargs -0 -r -P "$FILTER_JOBS" -n 1 bash -c 'record_input "$1"' _
        echo "[+] RECORDED, BY EXIT CODE:"
        find "$FILTERED_DIR" -maxdepth 1 -type f | sed 's/.*\.//' | sort | uniq -c
    fi

    if [ -z "$SKIP_MINIMIZATION" ]; then
        do_minimization "$CORPUS_DIR" "$SEED_DIR"
        INDIR="$SEED_DIR"
    else
        INDIR="$CORPUS_DIR"
    fi

    # The dry run is the first run of every seed, so the first seed with an FSan
    # violation exits 99 and is skipped: with a single seed, AFL++ would give up.
    if [ "$(ls "$INDIR" | wc -l)" -eq 1 ]; then
        SEED=$(ls "$INDIR")
        cp "$INDIR/$SEED" "$INDIR/$SEED.copy"
    fi
fi

# set up parameters
"$AFL_BASE/afl-system-config"
HOURS=${HOURS:-72} # 3 day runs
FUZZ_SECONDS=$((HOURS * 3600)) # not SECONDS, which bash counts up

echo "Fuzzing on CORE $PINNED_CORE"
FUZZ_CMD=("$AFL_BASE/afl-fuzz" -i "$INDIR" -o "$OUTDIR" -b "$PINNED_CORE" -V "$FUZZ_SECONDS" -t "${FUZZ_TOUT}+")
if [ -n "$WITH_DICTIONARY" ]; then
    FUZZ_CMD+=(-x "$WITH_DICTIONARY")
fi
# AFL++ seeds its RNG at random; RNG_SEED fixes it (-s), to repeat a run.
if [ -n "${RNG_SEED:-}" ]; then
    echo "Using RNG seed: $RNG_SEED"
    FUZZ_CMD+=(-s "$RNG_SEED")
fi
FUZZ_CMD+=(-- "$HARNESS_FULLPATH" @@)

# do the fucking fuzzing
"${FUZZ_CMD[@]}"
