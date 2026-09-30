#!/usr/bin/env bash

# for each found crash location, gimme an input that triggers that crash on that fuzzer
CRASH_LOCS=`cat /fuzzing-campaign/*txt | grep MISM| cut -f2 -d"(" | cut -f1 -d")"`
UNIQ_CRASH_LOCS=`echo $CRASH_LOCS | sort -u | tr ' ' '\n' | sort -u | tr '\n' ' '`
if [ -z $UNIQ_CRASH_LOCS ] ; then
    echo "No mismatches found."
    echo "DBG CRASH_LOCS: $CRASH_LOCS"
    echo "DBG UNIQ_CRASH_LOCS: $UNIQ_CRASH_LOCS"
    exit 1
fi

DUP_NUM_CRASH_LOCS=`echo $CRASH_LOCS | wc -l` # with duplicates
CRASH_LOC_NUM=`echo $UNIQ_CRASH_LOCS | wc -l`

# echo "Overall crashes: $DUP_NUM_CRASH_LOCS"
# echo "Unique crash locations: $CRASH_LOC_NUM"

# store crashing inputs
mkdir -p /fuzzing-campaign/tag-mismatches/ || true
let id=0
# create file to store all crash outputs
echo "" > /fuzzing-campaign/output.txt

echo $UNIQ_CRASH_LOCS | tr ' ' '\n' | while read UN_LOC; do
    FUZZER=$(echo $UN_LOC | cut -f1 -d"+")
    OFFSET=$(echo $UN_LOC | cut -f2 -d"+")
    CRASHING_INPUT=$(grep -B1 $UN_LOC /fuzzing-campaign/*txt | head -1 | cut -f2 -d" ")
    BASEFUZZER=$(basename $FUZZER)
    NEW_CRASHING_INPUT=/fuzzing-campaign/tag-mismatches/${BASEFUZZER}_${id}_$OFFSET
    cp -r $CRASHING_INPUT $NEW_CRASHING_INPUT
    echo "$FUZZER $NEW_CRASHING_INPUT" 2>&1 | tee -a /fuzzing-campaign/output.txt
    $FUZZER $NEW_CRASHING_INPUT 2>&1 | tee -a /fuzzing-campaign/output.txt
    
    let id=$id+1
done