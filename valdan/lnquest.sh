#!/bin/bash
# Recreates hard links on quest.ms.mff.cuni.cz. Must be run after git pull
# if git rewrites one of the linked files (because then the link breaks).
# Copyright © 2019, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

cd /home/zeman/unidep/docs-automation/valdan
if [[ "$(pwd)" == "/home/zeman/unidep/docs-automation/valdan" ]] ; then
    # Not everything should be available in the higher folder.
    # For example, validate_all.pl must be run from its location, otherwise it will not find the list of languages.
    ###!!! I am not sure what was the original reason for accessing the scripts via hard links.
    ###!!! I think that symlinks might work as well but I suspect I would have used them had there been no trouble with it.
    for i in githook.pl clone_one.sh validate.sh update-validation-report.pl validation-report.pl queue_validate.pl README* ; do
        rm -f ../../$i
        ln $i ../../$i
    done
else
    echo Failed to enter the target folder.
fi
