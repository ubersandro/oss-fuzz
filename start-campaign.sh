#!/usr/bin/env bash
# set -x

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <harness_path> <project_name>"
    exit 1
fi

export AFL_AUTORESUME=1

# export AFL_IGNORE_SEED_PROBLEMS=1
export AFL_PIZZA_MODE=-1

# do not detect leaks
export AFL_BASE=$SRC/aflplusplus/
export HWASAN_OPTIONS=verbosity=0:detect_leaks=0:abort_on_error=1:symbolize=0
unset HWASAN_SYMBOLIZER_PATH

HARNESS_FULLPATH=$(realpath $1)
PROJECT_NAME=$2
INSTANCES=${INSTANCES:-1}
PRODUCE_OUTPUT=${PRODUCE_OUTPUT:-1}
PINNED_CORE=${PINNED_CORE:-0} # only meaningful when INSTANCES=1, otherwise cores are automatically assigned from the E_CORE_LIST
WITH_DICTIONARY=${WITH_DICTIONARY:-""}

echo "Using harness: $HARNESS_FULLPATH"
echo "Using project name: $PROJECT_NAME"
echo "Using instances: $INSTANCES"
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
pip install tqdm

# download corpus 
wget -O /tmp/corpus.zip "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${PROJECT_NAME}_${HARNESS_NAME}/public.zip" || wget -O /tmp/corpus.zip "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${HARNESS_NAME}/public.zip"

CORPUS_DIR="$OUT/corpus-${HARNESS_NAME}"
rm -rf "$CORPUS_DIR" 2>/dev/null || true # clear 
unzip -o /tmp/corpus.zip -d "$CORPUS_DIR" 2>&1 >/dev/null 2>&1 
echo "[+] CORPUS DOWNLOADED AND UNPACKED! SIZE IS: $(ls $CORPUS_DIR | wc -l)"
sleep 1

#create filter dir
FILTERED_DIR=/crashes-$HARNESS_NAME
rm -rf $FILTERED_DIR 2>/dev/null || true
mkdir -p $FILTERED_DIR 2>/dev/null || true

let N=$(ls "$CORPUS_DIR" | wc -l)
let x=0

if [ -z "$SKIP_FILTERING" ]
then
for input in "$CORPUS_DIR"/*; do
    timeout -s KILL 2s "$HARNESS_FULLPATH" "$input" >/dev/null 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] Input $input caused a timeout or crash (exit code: $rc), MOVING IT."
        mv "$input" "$FILTERED_DIR"
    fi
    wait $!
    let x=x+1
    if [ $((x % 1000)) -eq 0 ]; then
        echo "[+] Processed $x / $N inputs..."
    fi
done
fi 
set -x
echo "[+] CORPUS FILTERED:"
echo "[+] FOUND CRASHES/HANGS IN CORPUS: $(ls $FILTERED_DIR | wc -l) files"
sleep 1
CMIN_TOUT="${CMIN_TOUT:-20}"
# if any corpus, minimize
if [ "$(ls -A $CORPUS_DIR)" ]; then
    echo "[+] CORPUS NOT EMPTY, PROCEEDING TO MINIMIZATION."
    MINIMIZED_DIR="$OUT/corpus_cmin-${HARNESS_NAME}"
    rm -rf "$MINIMIZED_DIR" 2>/dev/null || true
    echo "[+] MINIMIZING CORPUS WITH AFL-CMIN: CURRENT SIZE IS: $(ls $CORPUS_DIR | wc -l)"
    $AFL_BASE/afl-cmin -t $CMIN_TOUT -i "$CORPUS_DIR" -o "$MINIMIZED_DIR" -m none -T 24 -- $HARNESS_FULLPATH @@
    echo "[+] CORPUS MINIMIZED: NEW SIZE IS: $(ls $MINIMIZED_DIR/ | wc -l)"
    sleep 1
    CORPUS_DIR="$MINIMIZED_DIR"
else
    echo "[+] CORPUS IS EMPTY, SKIPPING MINIMIZATION."
fi

E_CORE_LIST=( {8..23} )

$AFL_BASE/afl-system-config

SECONDS=$((36 * 3600))
FUZZ_TOUT="${FUZZ_TOUT:-100}"

if [ "$INSTANCES" -eq 1 ]; then
    # if only one instance, pin to the core specified by PINNED_CORE
    E_CORE_LIST=($PINNED_CORE)
fi

for i in $(seq 0 $(($INSTANCES-1))); do
    core=${E_CORE_LIST[$i]}
    outdir="$OUT/${HARNESS_NAME}_${i}"
    instance_corpusdir="$OUT/${HARNESS_NAME}_${i}"
    rm -rf "$outdir" 2>/dev/null || true
    rm -rf "$instance_corpusdir" 2>/dev/null || true
    cp -r $CORPUS_DIR "$instance_corpusdir" # this might be empty
    echo "launching instance $i on core $core"
    # DO NOT USE SHARED MEMORY, PARALLEL FUZZING ETC. 
    # just 10 independent afl-fuzz instances with identical copy of the corpus, each pzinned to a different E-core, fuzzing for 12h
    # -m none as a default
    
    OUT_REDIR=""
    RANDOM_NUMBER=$RANDOM
    DICT=""
    # if [ ! "$WITH_DICTIONARY" -eq "" ]; then
    if [ ! -z "$WITH_DICTIONARY" ]; then
        DICT=" -x ${WITH_DICTIONARY} "
    fi
    CMD="AFL_SEED=$RANDOM $AFL_BASE/afl-fuzz -i \"$instance_corpusdir\" -o \"$outdir\" -b$core -V $SECONDS $DICT -t $FUZZ_TOUT+ -- $HARNESS_FULLPATH @@"
    if [ "$PRODUCE_OUTPUT" -eq 0 ]; then
        CMD="$CMD > /dev/null 2>&1"
    fi

    eval "$CMD &"
done

wait $!
echo DONE!
echo CONTENT OF OUT DIRECTORIES for CRASHES :k

ls -l $OUT/$HARNESS_NAME*/crashes

