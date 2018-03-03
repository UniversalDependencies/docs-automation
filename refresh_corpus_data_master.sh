#!/bin/bash
# Receives a list of directories of UD repos to rerun
# Switches each repo to master before collecting data. Switches back to dev afterwards.
# This way we collect information relevant to the most recent official UD release (provided the repos are up-to-date).

if [[ "$1" == "--pull" ]] ; then
  PULL=1
  shift
else
  PULL=0
fi

OUTDIR="_corpus_metadata"
mkdir -p $OUTDIR

for repo_dir in $*
do
    echo ==================================================
    echo $repo_dir
    pushd $repo_dir
    # In general, the UD front page should show information based on the master branch.
    # However, for upcoming treebanks (not released before), the dev branch should be used instead.
    git checkout master
    if [ $PULL == 1 ] ; then
        git pull
    fi
    if ls *.conllu 1> /dev/null 2>&1 ; then
      echo conllu files found
    else
      echo conllu files not found, switching back to dev
      git checkout dev
      if [ $PULL == 1 ] ; then
          git pull
      fi
    fi
    popd
    echo $(basename $repo_dir)
    python3 corpus_stats.py --readme-dir $repo_dir --repo-name $(basename $repo_dir) --codes-flags ./codes_and_flags.yaml --json $repo_dir/*-ud-{train,dev,test}*.conllu > $OUTDIR/$(basename $repo_dir).json
    pushd $repo_dir
    git checkout dev
    popd
    echo "done"
done
