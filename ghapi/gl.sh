#!/bin/bash
# Call this with --no-expand-tabs if we want to read and parse the output.

folder=$(pwd | perl -pe 'chomp; s:.*/::')
conllu=$(ls -1 | grep -P '\.conllu' | wc -l)
git log --reverse --pretty='format:'$folder'%x09'$conllu'%x09%C(auto)%ai%x09%h%x09%an%x09%s' $@

# History of UD repo creation:
# for i in UD_* ; do cd $i ; gl --no-expand-tabs | head -1 ; cd .. ; done | tee udrepoage.txt
# grep -P '\t0\t' udrepoage.txt | sort -k3 -r

