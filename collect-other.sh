#!/usr/bin/env bash 
# spits out a list of inputs (names) that crashed for some reason, but not for tag mismatches
INPUT_PREFIX="${INPUT_PREFIX:-}" 
FUZZER_PATH="${FUZZER_PATH:-}"

INPUTS=`grep -B1 OTHER /fuzzing-campaign/*txt | cut -d" " -f2| grep -v "\-\-" | sed 's/\/fuzzing-campaign\///g' | sort -u`
for i in $INPUTS; do
  # FUZZER_NAME=$(echo $i | cut -d"/" -f1 | cut -d"_" -f1)
    FUZZER_NAME=$(echo $i | cut -d"/" -f1 | sed 's/_0.*//g')

  echo -n "$FUZZER_PATH${FUZZER_NAME}"
  echo " $INPUT_PREFIX$i"
done