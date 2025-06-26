#!/bin/bash
# Runs validate.py (format validation of UD treebanks).
# Copyright © 2018, 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# This script may be invoked from a CGI script. Therefore it must be able to
# run under user www-data.

# User www-data may not have the proper locale to process UTF-8 input. Python
# will throw an exception if this is the case.
export LC_ALL=en_US.utf8

echo `date` validating $*
START=$(date +%s.%N)

# Validate.py depends the regex module that may not be installed system-wide.
# In addition, in June 2025 I am experimenting with making it dependent on
# Udapi, which itself is dependent on colorama and termcolor. The on-line
# validation will be invoked by user www-data, who must have access to the same
# version of Python with the same packages installed. Therefore, I created a
# virtual environment, installed the packages there, and I am activating the
# environment here before we launch the validator. Moreover, I am not using the
# version of Udapi from pip but I have a copy of udapi-python from GitHub
# instead. The PYTHONPATH variable will tell Python where to find Udapi.
source .venv/bin/activate
export PYTHONPATH=/usr/lib/cgi-bin/unidep/udapi-python

# Finally, we assume that validate.py itself resides in a local clone of the
# tools repository from UD GitHub.
python3 tools/validate.py $*

END=$(date +%s.%N)
ELAPSED=$(echo "$END - $START" | bc)
echo "Elapsed time: ${ELAPSED} seconds"
