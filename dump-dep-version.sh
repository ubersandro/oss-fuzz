#!/usr/bin/env bash
# Print the checked-out commit of every dependency cloned for each project.
# Usage: ./dump_dep_commits.sh DEPS_FILE > commits.tsv
set -u
deps_file=${1:?usage: $0 DEPS_FILE}

# git clone options that take a separate argument.
declare -A opt_with_arg=([--branch]=1 [-b]=1 [--depth]=1 [--origin]=1 [-o]=1
                         [--config]=1 [-c]=1 [--jobs]=1 [-j]=1)

# Print the directory a "git clone ARGS..." creates: the explicit destination
# if there is one, else the last URL component without ".git".
dep_dir() {
  local url= dest= w
  while (($#)); do
    w=$1; shift
    case $w in
      '||' | '&&' | ';' | '\') break ;;
      -*) [[ -n ${opt_with_arg[$w]:-} ]] && shift ;;
      *) if [[ -z $url ]]; then url=$w; else dest=$w; break; fi ;;
    esac
  done
  [[ -n $url ]] || return 1
  if [[ -z $dest ]]; then
    dest=${url%/}; dest=${dest##*/}; dest=${dest%.git}
  fi
  printf '%s\n' "$dest"
}

project=
declare -A seen=()
printf 'PROJECT\tDEPENDENCY\tCOMMIT\n'
while IFS= read -r line || [[ -n $line ]]; do
  line=${line%$'\r'}
  if [[ $line =~ ^PROJECT:([^[:space:]]+) ]]; then
    project=${BASH_REMATCH[1]}
    seen=()
    continue
  fi
  # Only the first clone of a RUN line; "|| git clone" fallbacks clone the same repo.
  [[ -n $project && $line =~ ^RUN[[:space:]]+git[[:space:]]+clone[[:space:]]+(.*)$ ]] || continue
  read -ra words <<< "${BASH_REMATCH[1]}"
  dep=$(dep_dir "${words[@]}") || continue
  [[ -z ${seen[$dep]:-} ]] || continue
  seen[$dep]=1

  container="eval-eval-${project}-1"
  if out=$(docker exec "$container" git -c safe.directory='*' -C "/src/$dep" \
             log -1 --format='%H %cs %s' 2>&1 </dev/null); then
    printf '%s\t%s\t%s\n' "$project" "$dep" "$out"
  else
    printf '%s\t%s\tERROR: %s\n' "$project" "$dep" "${out//$'\n'/ }"
  fi
done < "$deps_file"