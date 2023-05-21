# Usage: REFRESH=../UD_Chinese-GSD make refresh
refresh:
	refresh_corpus_data.sh $(REFRESH)

refresh_all:
	refresh_corpus_data.sh --pull ../UD_*

dan:
	python3 at_glance.py --codes codes_and_flags.yaml --releases valdan/releases.json --genre genre_symbols.json --docs-dir ../docs _corpus_metadata/*.json --subset current > ../docs/_includes/at_glance.html
	python3 at_glance.py --codes codes_and_flags.yaml --releases valdan/releases.json --genre genre_symbols.json --docs-dir ../docs _corpus_metadata/*.json --subset sapling > ../docs/_includes/at_glance_sapling.html
	python3 at_glance.py --codes codes_and_flags.yaml --releases valdan/releases.json --genre genre_symbols.json --docs-dir ../docs _corpus_metadata/*.json --subset retired > ../docs/_includes/at_glance_retired.html
	perl list_lang_spec_docs.pl --codes codes_and_flags.yaml --docs-dir ../docs > ../docs/_includes/lang_spec_docs.html

all: refresh_all dan
	cd ../docs
	git pull --no-edit
	git status
