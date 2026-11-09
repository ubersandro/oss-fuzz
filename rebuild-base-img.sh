#!/usr/bin/env bash
# rebuild FSan base and FSan-codeql
set -xeu
pushd ~/ubersandro
docker buildx build -t fsan-afl -f oss-fuzz/Dockerfile --progress=plain . 
docker buildx build -t fsan-afl-codeql -f oss-fuzz/CodeQL-Dockerfile --progress=plain .
docker buildx build -t fsan-afl-24 -f oss-fuzz/Dockerfile-24 --progress=plain .
docker buildx build -t fsan-afl-codeql-24 -f oss-fuzz/CodeQL-Dockerfile-24 --progress=plain .
popd
