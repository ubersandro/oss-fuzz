#!/usr/bin/env bash
CONTAINERS=`docker ps -a | grep eval | awk '{print $1}'`
for c in $CONTAINERS; do
    echo "CONTAINER $c"
    docker cp ./results.sh $c:/src/results.sh
    docker cp ./output.py $c:/src/output.py
    docker cp ./output-full.py $c:/src/output-full.py
    docker cp ./codeql-oss-fuzz $c:/usr/local/bin/codeql-oss-fuzz
    docker cp ./start-campaign.sh $c:/src/fuzz.sh
    docker cp ./codeql/codeql-struct-punning $c:/src/codeql-struct-punning
    docker cp ./collect-fuzzer-output.sh $c:/src/collect-fuzzer-output.sh
    docker exec $c bash -c "chmod +x /src/results.sh"
    docker exec $c bash -c "chmod +x /src/collect-fuzzer-output.sh"
    docker cp ./gather-other.sh $c:/src/gather-other.sh
    docker exec $c bash -c "chmod +x /src/gather-other.sh"
    docker cp ./post-processing.sh $c:/src/post-processing.sh
    docker exec $c bash -c "chmod +x /src/post-processing.sh"
done