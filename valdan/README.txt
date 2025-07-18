This is Dan's implementation of the automatic validation of UD data.
The scripts should ideally lie in a CGI-accessible folder so that
GitHub web hook can invoke them upon push to a UD repository. At
the same time, all UD data repositories should be cloned as subfolders
of that CGI folder. That poses a problem for versioning of the scripts
themselves (we want to avoid nested git folders). Therefore I recommend
to have this repository (docs-automation) checked out as a sibling to
the UD data repositories, and to symlink from the CGI folder down here
to the real (and versioned) implementation of the scripts; the same
can be done with other important files including this README.

cgi/unidep
+- UD_Afrikaans
+- ...
+- UD_Yoruba
+- tools
+- docs-automation
|  +- valdan
|     +- githook.pl
+- githook.pl ---> symlink to docs-automation/valdan/githook.pl

You must configure your web server to follow symlinks for this to
work. Otherwise the server will send '403 Forbidden' back to
GitHub, and it will not invoke the script. If you cannot configure
your web server, maybe you have to use a hard link or just a copy
of the script. (In fact, a hard link is probably not much better than
a copy, because when such a file changes on GitHub, a git pull in
docs-automation will first unlink the versioned file, then create
a new one, hence the file in the main folder will become independent
and outdated. Calling the script docs-automation/valdan/lnquest.sh
will re-connect the files again, but at this point we could as well
call a script that copies the files instead of hardlinking them.)

Other than the above, the main cgi folder should contain only log
files in the 'log' subfolder, and the folders 'perllib' and
'pythonlib' with locally installed modules. These are not
versioned.



# Hard Links vs. Symlinks vs. Copies

If it is not possible to configure Apache to follow symlinks in the cgi-bin
folder, we may use hard links between scripts in the main folder and their
versioned copies in docs-automation/valdan.

Note that git pull in docs-automation will break the hard links because git
first removes (i.e., unlinks) the old file and then creates a new file, instead
of simply writing in the old file. We can run the script lnquest.sh after git
pull and it will recreate the hard links.

The hard links will obviously be broken also if the whole validation
application is copied to a new server. The script lnquest.sh can be used to
restore them but it has to be edited first, as there are hard-coded paths in
it.

Note: In the current installation on quest, we have hard links for the two
scripts that are accessed directly through the web server: githook.pl and
validation-report.pl. The other scripts that are called from githook.pl or
manually in the terminal (such as update-validation-report.pl) are symlinked
but the symlinks do not work for the directly accessed scripts ('403
Forbidden'). On the other hand, there are other scripts in docs-automation/
valrules. Here the whole folder is symlinked as langspec from the main folder.
The scripts inside are accessed directly through the web server and it works.
The probable explanation is that the options currently set for the cgi-bin
folder (in /etc/apache2/conf-enabled/serve-cgi-bin.conf) contain
+SymLinksIfOwnerMatch. This is difficult to achieve for individual scripts.
The first clone of the docs-automation repository as well as the symlinks are
created by user zeman, but when new version arrives from GitHub, the new file
is created by user www-data. On the other hand, symlinking a subfolder is safer
because the subfolder is not recreated when files are updated inside it.
Alternatively, we could replace the option with +FollowSymLinks and it should
work regardless of who is the owner of the files. The server has to be
restarted when its configuration has changed.

  sudo systemctl restart apache2



# Access Permissions

User www-data must have write access to all treebank folders, to
the 'docs' and 'tools' repos, to the 'log' folder, and to all files
and subfolders of these folders. Furthermore, the mask must be set
so that any new files I create (e.g. via git pull) will automatically
grant access to user www-data. Similarly, the mask of user www-data
must ensure that any files created by that user will be writable by me.
All this can be achieved with the setfacl command (access control lists).
See the script clone_one.sh for how it is done when cloning a new UD
treebank.

The UD data repositories must be cloned via the HTTPS protocol (as
opposed to SSH) because the CGI scripts run under the user www-data
and cannot use my personal SSH key to sign in to GitHub. Their
files and subfolders must grant rwx permissions to the user www-data.
We cannot use chmod to change the permissions because git would consider
it a local change of the files and would refuse to pull new revisions before
the local changes are committed. However, we can use the extended rights
management with access control lists (setfacl). The following script can
be used to clone the repositories.

  clone_one.sh UD_Afrikaans

Note that the clone_one.sh script modifies default rights for newly
created files so that both the users 'www-data' and 'zeman' get
full access. If the www-data adds new files by git pull, I still
want to be able to remove them when necessary. If you are installing
this infrastructure on your server, you probably want to change 'zeman'
to your username. And you may want to verify that the CGI scripts indeed
run as user 'www-data' on your system.

Private repositories must be excluded from automatic validation
because they require authentication even for git pull via HTTPS.
(At the time of this writing we have one private UD treebank:
UD_Korean-Sejong.)

Similarly to the UD treebank folders, the repository 'tools' must
also be cloned with complete access permissions for the users zeman
and www-data. (But unlike the treebank repositories, tools should
stay in the master branch.)

Now we need a folder called log, lying in cgi/unidep next to the UD
repositories, with write access for user www-data:

  mkdir log
  setfacl -R -m u:www-data:rwx log
  setfacl -R -m u:zeman:rwx log

Finally, user www-data also needs write access to four files that
reside directly in the main cgi folder:

  validation-report.txt
  validation-report.bak
  evaluation-report.txt
  evaluation-report.bak

The main script that must be symlinked or copied to cgi/unidep is
githook.pl. This script will be invoked by a POST request from
GitHub when a user pushes to a UD repository. The URL of the script
must be registered with the UniversalDependencies organization on
GitHub:

https://github.com/organizations/UniversalDependencies/settings/hooks

Currently, the URL pointing to Dan's installation is

http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/githook.pl

GitHub shows a list of recent "payloads" sent to the githook
script. If it shows a red icon and a warning that the payload could
not be delivered before timeout, it does not necessarily mean that
the process was really unsuccessful. We need a lot of time to get
the updated data and process them, and Apache will not send the
output of the githook script (i.e., our response to GitHub) before
we are done. GitHub may thus think that we are not responding
despite everything being OK at our end.



# Git Configuration

Newer versions of git will by default report an error if a git folder
is owned by a user other than the parent folder, as it is seen as a
security risk. However, the contents of our repository is typically
updated by two users (me and www-data), with file/folder ownership
alternating depending on who fetched the object first. Assuming that
the validation is running on a dedicated virtual server with its own
file system, the security risk is not significant, so we can turn the
git rule off. We have to do it system-wide, so that it also applies
to user www-data.

  sudo git config --system --add safe.directory '*'



# Perl and Python Libraries

The validation server uses Perl and Python with certain libraries
that must be installed separately. It is possible to install them
without root permissions to local folders called 'perllib' and
'pythonlib' but we must tell Perl and Python where to find them.

Perl needs the module LWP::Simple. It can be installed as an Ubuntu
package:

  sudo apt-get install libwww-perl

Perl further needs the modules JSON::Parse and YAML. I was not able
to find corresponding Ubuntu packages (libjson-perl and
libconfig-json-perl did not help), but they can be installed
directly from CPAN:

  sudo cpan JSON::Parse
  sudo cpan YAML

Additionally, the infrastructure for registering language-specific
features, relation subtypes, auxiliaries etc. needs the module CGI.

  sudo cpan CGI

If we do not have superuser access to the server, we can install
them to the user-writable space, then copy them to the cgi folder
and always call Perl with the -I option, telling it where the
libraries are. This is in fact what our scripts do when invoking
other scripts, which need the libraries (see for example the source
code of update-validation-report.pl). However, simple copying of
the library folder from one server to another is likely to cause
problems, as the libraries may be compiled for a different
architecture. Even if we install the libraries with superuser
permissions to the system space, we want to make sure that their
copies from the other architecture are erased from the local
perllib. On the other hand, the local perllib also contains some of
my own Perl libraries (starting with a lowercase letter and ending
with '.pm'); we want to keep these, as one of the validation
scripts uses them.

As for Python, we need the tool 'pip3' to install additional
modules. The tool is available as a package for Ubuntu:

  sudo apt-get install python3-pip

Once we have pip3, we can install the modules 'regex', 'colorama',
'termcolor', and 'udapi'. If we do it with sudo, it should by installed
system-wide and thus usable by the user www-data. Without sudo it will
be installed in our home folder and we will have to copy the installation
to the folder 'pythonlib' in the cgi folder.

  sudo pip3 install regex

The other option is to install locally for the current user:

  pip3 install --user regex

then copy ~/.local/lib/python3.4 to pythonlib/python3.4

We have shell envelopes for Python scripts that we use, and these
envelopes first set PYTHONLIB to point to the local pythonlib.
(They also set locale to digest UTF8 input.) These settings are
essential and the user www-data does not have them by default.



# Apache Configuration

To turn on CGI functionality of the web server, it may be necessary
to turn on the Apache module cgid, which does not seem to be on by
default. We may also need to symlink from /var/www/cgi-bin to
/usr/lib/cgi-bin.

  https://code-maven.com/set-up-cgi-with-apache

See the Apache documentation on configuration options, e.g., for
the HTTP Server 2.4, see

  https://httpd.apache.org/docs/2.4/configuring.html

The main configuration file is typically called 'httpd.conf' but
depending on system, other files may be relevant. For example, this
may be the entry point for a virtual host:

  /etc/apache2/sites-enabled/000-default.conf

If the validation report is the only content or service provided by
the server, we may want to redirect the top-level URL to the actual
script that produces the report. This can be achieved by adding the
following directive to the configuration file (adjust to the actual
URL of the final script on your machine):

  Redirect /index.html "http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/validation-report.pl"

Whenever we change the configuration of the server, we must restart
the server:

  sudo service apache2 reload

Now we can test the new behavior in the browser.



# Validation Wrapper Scripts

* `tools/validate.py` is the official validator. We do not call it directly.
  Instead, we use wrapper scripts that can be found in `docs-automation/valdan`
  and that are described below.
* `validate.sh` sets `PYTHONPATH`, activates the virtual environment and calls
  `validate.py`. The arguments are CoNLL-U files of one treebank.
* `update-validation-report.pl` is applied to one or more treebanks (its
  arguments are treebank names). For each treebank it first updates its local
  clone using `git pull`, then it runs `validate.sh` on it. Finally it
  interprets the validation result and updates `validation-report.txt`, which
  contains the most recent validation results of all treebanks. This script
  also makes sure that the validator's output is saved in <treebank-name>.log,
  e.g., log/UD_Czech-PUD.log. A shorter summary is printed together with other
  progress reports to STDERR. When invoked by git hook, STDERR of this script
  is typically redirected to the global log `log/validation.log`.
* `queue_validate.pl` is a wrapper around `update-validation-report.pl`. It
  maintains a queue of treebanks to be validated in the file `queue.txt`. If
  another process is already validating treebanks from the queue, it will only
  add the new treebanks to the queue and exit. Otherwise it will create the
  queue and start validating the treebanks. This helps with two issues:
  * If we make, within a short time span, two changes that result in
    revalidating all treebanks (which may take several hours to complete), the
    validator will not process every treebank twice. When the second change is
    detected, only the treebanks processed so far will be re-introduced to the
    queue.
  * We do not want two validation processes running on the same treebank at the
    same time. That would result in a corrupt validation report (with both
    processes attempting to write to the same log file).
* `validate_all.pl` runs `queue_validate.pl` for all treebanks, or all
  treebanks of given languages (their codes can be given as arguments).
* `githook.pl` is called by the web hook registered on GitHub. It analyzes the
  changes on GitHub, decides which treebanks must be revalidated and calls
  either `validate_all.pl`, or directly `queue_validate.pl`.
