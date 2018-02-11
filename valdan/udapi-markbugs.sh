#!/bin/bash
# Runs Udapi ud.MarkBugs (content validation of UD treebanks).
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# This script may be invoked from a CGI script. Therefore it must be able to
# run under user www-data.

# User www-data may not have the proper locale to process UTF-8 input. Python
# will throw an exception if this is the case.
export LC_ALL=en_US.utf8

# Udapi depends on a few Python modules that may not be installed system-wide.
# If we followed the instructions in Udapi's README, pip3 installed the modules
# into our home: ~/.local/lib/python3.4/site-packages. However, user www-data
# will not find the packages there. Hence we assume that ~/.local/lib/python3.4
# has been recursively copied to the current folder as pythonlib.
export PYTHONPATH=pythonlib/site-packages

# Finally, we assume that Udapi itself also exists (as a clone of the Github
# repository) in the current folder, in a subfolder named udapi-python. We will
# now call it and let it take care of our STDIN and STDOUT.
python3 udapi-python/bin/udapy ud.MarkBugs
