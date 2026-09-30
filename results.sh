#!/bin/bash
mkdir -p /fuzzing-campaign/FUZZING_QUEUES || true
# assumes fuzzers live in /out
# copy crashes from OSS-Fuzz fuzzer queues
set -x 
for fuzzer in `find  /out/ -maxdepth 1 -type f -executable -name '*uzz*'  | grep -v corpus | sort -u`;    do
        echo "Checking fuzzer: $fuzzer" 
        FUZZER_NAME=$(basename $fuzzer)
        mkdir -p /fuzzing-campaign/FUZZING_QUEUES/${FUZZER_NAME} || true
        cp -r /crashes-$FUZZER_NAME/*134  /fuzzing-campaign/FUZZING_QUEUES/${FUZZER_NAME}
        /src/collect-fuzzer-output.sh $fuzzer 2>&1 | tee /fuzzing-campaign/${FUZZER_NAME}.txt
        # exit 1
done