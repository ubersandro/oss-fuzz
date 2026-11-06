### Fuzzing with FSan
PRE: use database.csv with 2y of oss-fuzz reports from Jul 26 to Jul 24
1. generate project data and dump projects in projects.txt
    - python3 scrape-and-rank.py > statistics.txt (creates projects.txt)
2. generate harness data scraping fuzz-introspector
    - 
3. generate folder hierarchy for fuzzing campaign
4. build FSan base image
5. ./build-containers.sh $(realpath tofuzz.txt)
6. docker compose up
7. ./trigger-builds.sh
8. ./trigger-fuzzers.sh


## NOTES
1. the imagemagick fuzzers pollute the tmp directory (use watchdog to clean out)
2. do not build all projects at once (RAM wall)
3. always git add and commit the inputs POST fuzzing and triage (& output gen)

./rebuild-base-img.sh
./build-containers.sh $(realpath tofuzz.txt)
