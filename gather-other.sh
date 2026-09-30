#!/usr/bin/env bash

# for each found crash location, gimme an input that triggers that crash on that fuzzer
OTHER_CRASHES=`cat /fuzzing-campaign/*txt | grep -B1 OTHER`
FPE=`cat /fuzzing-campaign/*txt | grep -B1 FPE`
OOM=`cat /fuzzing-campaign/*txt | grep -B1 out-of-memory`
SEGV=`cat /fuzzing-campaign/*txt | grep -B1 SEGV`
ALLO_SIZE_TOO_BIG=`cat /fuzzing-campaign/*txt | grep -B1 "too-big"`
CHECK_FAILED=`cat /fuzzing-campaign/*txt | grep -B1 "CHECK"`
ASSERTION_FAILED=`cat /fuzzing-campaign/*txt | grep -B1 "ASSERT"`
ASSERTION_FAILED2=`cat /fuzzing-campaign/*txt | grep -B1 "ssert"`

UNKNOWN=`cat /fuzzing-campaign/*txt | grep -B1 OTHER| grep -v FPE| grep -v out-of-memory| grep -v SEGV| grep -v "too-big" | grep -v "CHECK"| grep -v "ASSERT"| grep -v "ssert"`
# TODO
echo $UNKNOWN