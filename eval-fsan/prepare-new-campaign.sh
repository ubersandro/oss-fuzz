#!/usr/bin/env bash

# copy all HARNESSES.txt files from final-fuzzing to NEW_DIR
OLD_DIR=$1
NEW_DIR=$2
PROJFILE=$3
if [ -z "$OLD_DIR" ] || [ -z "$NEW_DIR" ] || [ -z "$PROJFILE" ]; then
  echo "Usage: $0 <old_dir> <new_dir> <projfile>"
  exit 1
fi

if [ -d "$NEW_DIR" ]; then
  echo "Directory $NEW_DIR already exists. Please choose a different name."
  exit 1
fi

echo "Copying HARNESSES.txt files to $NEW_DIR"
# for project in $(cat $PROJFILE.txt); do
while read -r line; do
  project=$(echo "$line" | cut -d ":" -f 1)
  if [ -z "$project" ]; then
    echo "Warning: Empty project name found in $PROJFILE, skipping."
    continue
  fi
  if [ -f "$OLD_DIR/$project/HARNESSES.txt" ]; then
    mkdir -p "$NEW_DIR/$project"
    cp "$OLD_DIR/$project/HARNESSES.txt" "$NEW_DIR/$project/"
  else
    echo "Warning: HARNESSES.txt not found for $project, skipping."
  fi
done < "$PROJFILE"