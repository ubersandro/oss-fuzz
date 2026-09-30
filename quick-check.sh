#!/usr/bin/env bash
HARNESS=$1
BASE_HARNESS=$(basename $HARNESS)

for c in /fuzzing-campaign/${BASE_HARNESS}_0/default/crashes/*; do
        # if the file is the current directory itself or README, then skip
        if [ "$c" == "/fuzzing-campaign/${BASE_HARNESS}_0/default/crashes/README.txt" ]; then
                continue
        fi
        if [ "$c" == "/fuzzing-campaign/${BASE_HARNESS}_0/default/crashes/" ]; then
                continue
        fi
        $HARNESS $c 2>&1
done