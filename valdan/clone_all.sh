#!/bin/bash

for i in `cat ud-treebank-list.txt` ; do
    echo ====================
    echo $i
    clone_one.sh $i
    echo
done
