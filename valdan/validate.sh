#!/bin/bash
# Runs validate.py (format validation of UD treebanks).
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# This script may be invoked from a CGI script. Therefore it must be able to
# run under user www-data.

# User www-data may not have the proper locale to process UTF-8 input. Python
# will throw an exception if this is the case.
export LC_ALL=en_US.utf8

# Validate.py depends the regex module that may not be installed system-wide.
# If we installed it locally using pip install --user regex, it is now in our
# home: ~/.local/lib/python2.7/site-packages. However, user www-data will not
# find the packages there. Hence we assume that ~/.local/lib/python2.7 has been
# recursively copied to the pythonlib subfolder of the current folder.
export PYTHONPATH=pythonlib/python3.4/site-packages:/usr/lib/cgi-bin/unidep/udapi-python

# Finally, we assume that validate.py itself resides in a local clone of the
# tools repository from UD Github.
python3 tools/validate.py $*

