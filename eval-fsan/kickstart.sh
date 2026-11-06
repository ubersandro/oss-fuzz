#!/bin/bash

# python3 scrape-and-rank.py > statistics.txt
# stat projects.txt
# cat projects.txt | grep -v java | grep ":c" > projects-c.txt
# mv projects-c.txt projects.txt
# cat projects.txt | grep -v ":c++" > projects-c.txt
# cat projects.txt | grep ":c++" > projects-cpp.txt
# cat projects-c.txt projects-cpp.txt > projects-all.txt
# # opt.: move projects-all.txt to projects.txt
# mv projects.txt projects.txt.bak
# mv projects-all.txt projects.txt
# python3 generate-harness-data.py

# # now select 10 from C and 10 from C++
# head -10 projects-c.txt > tofuzz.txt
# head -10 projects-cpp.txt >> tofuzz.txt

PROJ_FILE=./tofuzz.txt python3 generate-compose.py
cat tofuzz.txt | cut -f1 -d":" > list
./build-containers.sh $(realpath list)