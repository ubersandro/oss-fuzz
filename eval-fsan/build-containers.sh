# TARGETS=(assimp ffmpeg imagemagick kimageformats mruby pcapplusplus gpac openbabel)
PROJ_FILE=$1
if [ -z "$PROJ_FILE" ]; then
    echo "Usage: $0 <projects-file>"
    exit 1
fi
touch build-containers.log
set -xe
pushd ~/ubersandro/oss-fuzz
cat $PROJ_FILE | cut -d ":" -f 1 | while read T; do
    grep -q ubuntu-24 ~/ubersandro/oss-fuzz/projects/$T/Dockerfile && echo "[+] $T WARNING: Dockerfile already uses ubuntu-24" | tee -a build-containers.log # ignore for now
    echo "[+] Building container for $T" | tee -a build-containers.log
    # grep "FROM gcr" projects/$T/Dockerfile && sed -i 's|^FROM.*|FROM fsan-afl-codeql:latest|' projects/$T/Dockerfile | tee -a build-containers.log
    python3 infra/helper.py build_image $T --no-pull   || echo "[!] $T build failed" | tee -a build-containers.log
done
popd