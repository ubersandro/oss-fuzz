#!/usr/bin/env bash
# set -x

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <harness_path> <project_name>"
    exit 1
fi

export AFL_AUTORESUME=1
export AFL_FUZZER_LOOPCOUNT=1000
# export AFL_IGNORE_SEED_PROBLEMS=1
export AFL_PIZZA_MODE=-1

# do not detect leaks
export AFL_BASE=$SRC/aflplusplus/
# some programs read the size of malloc/calloc calls from fuzzer-generated inputs. To allow them to continue, allocator_may_return_null=1
export HWASAN_OPTIONS=verbosity=0:detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1
unset HWASAN_SYMBOLIZER_PATH

HARNESS_FULLPATH=$(realpath $1)
PROJECT_NAME=$2
INSTANCES=${INSTANCES:-1}
PRODUCE_OUTPUT=${PRODUCE_OUTPUT:-1}
PINNED_CORE=${PINNED_CORE:-0} # only meaningful when INSTANCES=1, otherwise cores are automatically assigned from the E_CORE_LIST
# be smart and find the first core starting from 0 where NO FUZZER PROCESS is pinned
if [ $PINNED_CORE -eq 0 ]; then
    echo "Finding a free core to pin the fuzzer to..."
        for i in {0..190}; do
            if ! ps -e -o pid,psr,comm= | awk '{print $2,$3}' | grep -v defunc| grep -q "^$i afl-fuzz$"; then
                PINNED_CORE=$i
                break
            fi
        done
fi
echo "Using pinned core: $PINNED_CORE"
sleep 3
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
CORPUS_TMP_FILE="/tmp/corpus.${HARNESS_NAME}.zip"
wget -O $CORPUS_TMP_FILE "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${PROJECT_NAME}_${HARNESS_NAME}/public.zip" || wget -O $CORPUS_TMP_FILE "https://storage.googleapis.com/${PROJECT_NAME}-backup.clusterfuzz-external.appspot.com/corpus/libFuzzer/${HARNESS_NAME}/public.zip"

if [ -f "$CORPUS_TMP_FILE" -a -s "$CORPUS_TMP_FILE" ]; then
    echo "[+] CORPUS DOWNLOADED SUCCESSFULLY: $CORPUS_TMP_FILE"
    stat $CORPUS_TMP_FILE
else
    # check if something like HARNESSS_NAME*zip exists in /fuzzing-campaign, if so, use that as corpus
    if [ -d "/fuzzing-campaign" ]; then
        CORPUS_TMP_FILE=$(ls /out/${HARNESS_NAME}*.zip 2>/dev/null | head -n 1)
        if [ -f "$CORPUS_TMP_FILE" ]; then
            echo "[+] CORPUS FOUND IN /fuzzing-campaign: $CORPUS_TMP_FILE"
        else
            exit 1
        fi
    fi
fi
# rm -rf "$CORPUS_DIR" 2>/dev/null || true # clear 
CORPUS_DIR="$OUT/corpus-${HARNESS_NAME}"
unzip -o $CORPUS_TMP_FILE -d "$CORPUS_DIR" 2>&1 >/dev/null 2>&1 
echo "[+] CORPUS DOWNLOADED AND UNPACKED! SIZE IS: $(ls $CORPUS_DIR | wc -l)"
# if corpus file is in /tmp, remove it to save space
if [[ "$CORPUS_TMP_FILE" == "/tmp/corpus."*".zip" ]]; then
    rm -f $CORPUS_TMP_FILE 2>/dev/null || true
fi
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
    # DONT use KILL since it will produce zombies. Also, check on RC and wait in that order.
    taskset -c $PINNED_CORE timeout -s TERM 2s "$HARNESS_FULLPATH" "$input" >/dev/null 2>&1
    rc=$?
    wait $!
    
    if [ $rc -ne 0 ]; then
        echo "[!] Input $input caused a timeout or crash (exit code: $rc), MOVING IT. Idx $x / $N"
        mv "$input" "$FILTERED_DIR"/$(basename "$input").$rc
    fi
    
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
# if the harness is fuzz_route, set all TOUTs to 250
if [[ "$HARNESS_NAME" == *"fuzz_route"* ]]; then
    CMIN_TOUT=250
fi
# if any corpus, minimize
if [ "$(ls -A $CORPUS_DIR)" ]; then
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

E_CORE_LIST=( {8..23} )

$AFL_BASE/afl-system-config

SECONDS=$((72 * 3600)) # 3 day runs
FUZZ_TOUT="${FUZZ_TOUT:-100}"
# if the harness is fuzz_route in project gpac, set all TOUTs to 250
if [[ "$HARNESS_NAME" == *"fuzz_route"* ]] && [[ "$PROJECT_NAME" == *"gpac"* ]]; then
    FUZZ_TOUT=250
fi

if [ "$INSTANCES" -eq 1 ]; then
    # if only one instance, pin to the core specified by PINNED_CORE
    E_CORE_LIST=($PINNED_CORE)
fi

for i in $(seq 0 $(($INSTANCES-1))); do
    core=${E_CORE_LIST[$i]}
    # outdir="$OUT/${HARNESS_NAME}_${i}"
    if [ ! -d "/fuzzing-campaign" ]; then
        exit 1
    fi
    outdir="/fuzzing-campaign/${HARNESS_NAME}_${i}" # store campaign on host
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

