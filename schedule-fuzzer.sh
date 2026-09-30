#!/bin/bash

HARNESS_FILE="/fuzzing-campaign/HARNESSES.txt"

if [ ! -f "$HARNESS_FILE" ]; then
    echo "HARNESSES.txt file not found in /fuzzing-campaign/."
    exit 1
fi

if [ -z "${TMUX:-}" ]; then
    echo "This script must be run from inside the tmux session you want to use."
    exit 1
fi

PINNED_CORES_START="${PINNED_CORES_START:-0}"

if [ -z "${PROJECT:-}" ]; then
    echo "PROJECT is not set. Please set it to the project name."
    exit 1
fi

# Explicitly get the current tmux session.
CURRENT_SESSION="$(tmux display-message -p '#S')"

FUZZER_IDX=0
CURRENT_WINDOW=""

while IFS= read -r fuzzer || [ -n "$fuzzer" ]; do
    # Ignore empty lines
    [ -z "$fuzzer" ] && continue

    if [ ! -f "/out/$fuzzer" ]; then
        echo "Fuzzer $fuzzer does not exist in /out. Skipping."
        continue
    fi

    PINNED_CORE=$((PINNED_CORES_START + FUZZER_IDX))
    PANE_IDX=$((FUZZER_IDX % 4))

    if [ "$PANE_IDX" -eq 0 ]; then
        # First fuzzer of each group of 4: create a new window
        # in the current tmux session.
        CURRENT_WINDOW=$(
            tmux new-window -d -P -F '#{window_id}' \
                -t "${CURRENT_SESSION}:" \
                -n "$fuzzer" \
                bash -c "PINNED_CORE=$PINNED_CORE /src/fuzz.sh /out/$fuzzer $PROJECT; exec bash"
        )
    else
        # Add fuzzers 2, 3 and 4 as panes in this window.
        tmux split-window -d \
            -t "$CURRENT_WINDOW" \
            bash -c "PINNED_CORE=$PINNED_CORE /src/fuzz.sh /out/$fuzzer $PROJECT; exec bash"

        # Arrange all panes evenly.
        tmux select-layout -t "$CURRENT_WINDOW" tiled
    fi

    echo "FUZZER: $fuzzer  WINDOW: $CURRENT_WINDOW  PANE: $PANE_IDX  CORE: $PINNED_CORE"

    FUZZER_IDX=$((FUZZER_IDX + 1))

done < "$HARNESS_FILE"