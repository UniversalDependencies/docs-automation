# Receives a list of directories of UD repos to rerun
# Switches each repo to master before collecting data. Switches back to dev afterwards.
# This way we collect information relevant to the most recent official UD release (provided the repos are up-to-date).

OUTDIR="_corpus_metadata"
mkdir -p $OUTDIR

for repo_dir in $*
do
    pushd $repo_dir
    git checkout master
    popd
    echo $(basename $repo_dir)
    python3 corpus_stats.py --readme-dir $repo_dir --repo-name $(basename $repo_dir) --codes-flags ./codes_and_flags.yaml --json $repo_dir/*-ud-{train,dev,test}*.conllu > $OUTDIR/$(basename $repo_dir).json
    pushd $repo_dir
    git checkout dev
    popd
    echo "done"
done

