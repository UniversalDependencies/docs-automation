This repository contains code running the universaldependencies.org page automation.

# Treebank and language metadata and stats

The various components of the automation, especially the main language table, need metadata and stats gathered from the treebank data and the machine-readable section of the language readme. This is saved as a json file, one file per treebank, and is re-run every time anything changes in the corresponding treebank repository. All auto-generation scripts source from this json.

    repo_dir="/some/path/UD_Finnish-TDT"
    OUTDIR="_corpus_metadata"
    python3 corpus_stats.py --readme-dir $repo_dir --repo-name $(basename $repo_dir) --codes-flags ./codes_and_flags.yaml --json $repo_dir/*-ud-{train,dev,test}*.conllu > $OUTDIR/$(basename $repo_dir).json

or using the script:

    ./refresh_corpus_data.sh /some/path/UD_Lang1 /some/path/UD_Lang2

# Languages at glance table

The accordion table on the UD index page is included from `_includes/at_glance.html` by Jekyll. This file `at_glance.html` is produced using the `at_glance.py` script:

    python3 at_glance.py --codes codes_and_flags.yaml --genre genre_symbols.json _corpus_metadata/*.json > docs-src/_includes/at_glance.html

* `codes_and_flags.yaml` and `genre_symbols.json` are self-explanatory
* `*.json` is a bunch of per-treebank jsons produced as above

The script can be given `--skip empty` or `--skip withdata` to generate separate tables for languages with/without data.

The table is generated from the Jinja2 template in `templates/language.md`, with several custom filters found in `at_glance.py`. These are fed the data straight from the treebank jsons and refer to their structure. If you add any functionality, please keep the template tidy without complex ifs, and implement complex stuff as custom filters.

