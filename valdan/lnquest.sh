#!/bin/bash
# Recreates hard links on quest.ms.mff.cuni.cz. Must be run after git pull
# if git rewrites one of the linked files (because then the link breaks).
# Copyright © 2019 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

cd /home/zeman/cgi/unidep/docs-automation/valdan
if [[ "$(pwd)" == "/home/zeman/cgi/unidep/docs-automation/valdan" ]] ; then
    for i in *.sh *.pl ; do
    rm -f ../../$i
    ln $i ../../$i
    done
else
    echo Failed to enter the target folder.
fi
