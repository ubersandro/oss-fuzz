#!/bin/bash 
# CONTAINERS=`docker ps  | tr -s " "| cut -f1 -d" "| grep -v CONTAINER| grep eval`
CONTAINERS=`docker ps  | tr -s " "| cut -f1 -d" "| grep -v CONTAINER`

for c in $CONTAINERS; do
    echo "container $c"
    # docker exec $c tmux new-session -d -s build "cd \$SRC/\$PROJECT && /src/schedule-fuzzer.sh 2>&1 | tee /tmp/log; exec bash"
    # start command /src/schedule-fuzzer.sh in a new tmux session inside the container
    docker exec $c tmux new-session -d -s fuzzami "/src/schedule-fuzzer.sh; exec bash"
    # sleep 1
done
