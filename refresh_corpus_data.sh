# Receives a list of directories of UD repos to rerun

OUTDIR="_corpus_metadata"
mkdir -p $OUTDIR

for repo_dir in $*
do
    echo $(basename $repo_dir)
    python3 corpus_stats.py --readme-dir $repo_dir --repo-name $(basename $repo_dir) --codes-flags ./codes_and_flags.yaml --json $repo_dir/*-ud-{train,dev,test}*.conllu > $OUTDIR/$(basename $repo_dir).json
    echo "done"
done

