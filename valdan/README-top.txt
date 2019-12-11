# Versioning

A large part of this folder are clones of Github-hosted repositories. They contain the data
that we check. We synchronize them via git pull every time Github sends us a notification
that their contents has changed.

The scripts that make UD Validator work are versioned in docs-automation (see also the note
on hard links below). Other important files, including this README file, are versioned there
as well. This repository is not synchronized automatically.

Other than the above, this folder should contain only log files in the 'log' folder, and the
folders 'perllib' and 'pythonlib' with locally installed modules. These are not versioned.



# Hard Links

Some scripts in this folder are hard-linked with same-named scripts in docs-automation/valdan.
It's because I want to version the scripts and the docs-automation repository lies next to
the data repositories. However, as CGI scripts, they need to be invoked in the superordinate
folder.

I cannot use symlinks because the web server refuses to follow them. (But it could be probably
configured to follow them.)



# Access Permissions

User www-data must have write access to all treebank folders, to the docs and tools repos,
to the 'log' folder, and to all files and subfolders of these folders. Furthermore, the mask
must be set so that any new files I create (e.g. via git pull) will automatically grant
access to user www-data. Similarly, the mask of user www-data must ensure that any files
created by that user will be writable by me.

All this can be achieved with the setfacl command (access control lists). See the script
clone_one.sh for how it is done when cloning a new UD treebank.



# Other Notes

The validation server uses Perl and Python with certain libraries that must be installed
separately. It is possible to install them without root permissions to local folders
called 'perllib' and 'pythonlib' but we must tell Perl and Python where to find them.

