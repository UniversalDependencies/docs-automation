# Usage: REFRESH=../UD_Chinese-GSD make refresh
refresh:
	refresh_corpus_data.sh $(REFRESH)

refresh_all:
	refresh_corpus_data.sh --pull ../UD_*

dan:
	python3 at_glance.py --codes codes_and_flags.yaml --genre genre_symbols.json --docs-dir ../docs _corpus_metadata/*.json --skip empty > ../docs/_includes/at_glance.html
	python3 at_glance.py --codes codes_and_flags.yaml --genre genre_symbols.json --docs-dir ../docs _corpus_metadata/*.json --skip withdata > ../docs/_includes/at_glance_empty.html

all: refresh_all dan
	cd ../docs
	git pull --no-edit
	git status
