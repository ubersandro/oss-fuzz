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
FUZZERS_PER_WINDOW="${FUZZERS_PER_WINDOW:-8}"

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
    PANE_IDX=$((FUZZER_IDX % FUZZERS_PER_WINDOW))
    if [ ! -z $RESUME_CAMPAIGN ]; then
        CMD="PINNED_CORE=$PINNED_CORE RESUME_CAMPAIGN=1 /src/fuzz.sh /out/$fuzzer $PROJECT; exec bash"
    else
        CMD="PINNED_CORE=$PINNED_CORE /src/fuzz.sh /out/$fuzzer $PROJECT; exec bash"
    fi

    if [ "$PANE_IDX" -eq 0 ]; then
        # First fuzzer of each group: create a new window in the current tmux
        # session, showing each pane's title (the fuzzer) in its top border.
        WINDOW_AND_PANE=$(
            tmux new-window -d -P -F '#{window_id} #{pane_id}' \
                -t "${CURRENT_SESSION}:" \
                -n "$fuzzer" \
                bash -c "$CMD"
        )
        read -r CURRENT_WINDOW PANE_ID <<< "$WINDOW_AND_PANE"
        tmux set-window-option -t "$CURRENT_WINDOW" pane-border-status top
        tmux set-window-option -t "$CURRENT_WINDOW" pane-border-format ' #{pane_index}: #{pane_title} '
    else
        # Add the rest of the group as panes in this window. Splitting the
        # newest pane keeps pane numbers in HARNESSES.txt order.
        PANE_ID=$(
            tmux split-window -d -P -F '#{pane_id}' \
                -t "$PANE_ID" \
                bash -c "$CMD"
        )

        # Arrange all panes evenly.
        tmux select-layout -t "$CURRENT_WINDOW" tiled
    fi

    # Label the pane with its fuzzer.
    tmux select-pane -t "$PANE_ID" -T "$fuzzer"

    echo "FUZZER: $fuzzer  WINDOW: $CURRENT_WINDOW  PANE: $PANE_IDX  CORE: $PINNED_CORE"

    FUZZER_IDX=$((FUZZER_IDX + 1))

done < "$HARNESS_FILE"

# schedule job on another session that does 'find /tmp ! -name tmux* -type f -mmin +60 -delete' to clean up old files every 10 seconds
tmux new-session -d -s cleanup "find /tmp -maxdepth 1 ! -name tmux* -type f -mmin +60 -delete"