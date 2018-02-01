This is Dan's alternative and experimental implementation of the automatic validation
of UD data. The scripts should ideally lie in a CGI-accessible folder so that Github
web hook can invoke them upon push to a UD repository. At the same time, all UD data
repositories should be cloned as subfolders of that CGI folder. That poses a problem
for versioning of the scripts themselves (we want to avoid nested git folders).
Therefore I recommend to have this repository (docs-automation) checked out as a
sibling to the UD data repositories, and to symlink from the CGI folder down here
to the real (and versioned) implementation of the scripts.

cgi/unidep
+- UD_Afrikaans
+- ...
+- UD_Yoruba
+- tools
+- docs-automation
|  +- valdan
|     +- githook.pl
+- githook.pl ---> symlink to docs-automation/valdan/githook.pl

You must configure your web server to follow symlinks for this to work. Otherwise
the server will send '403 Forbidden' back to Github, and it will not invoke the
script. If you cannot configure your web server, maybe you have to use a hard link
or just a copy of the script.

The UD data repositories must be cloned via the HTTPS protocol (as opposed to SSH)
because the CGI scripts run under the user www-data and cannot use my personal
SSH key to sign in to Github. Their files and subfolders must grant rwx permissions
to the user www-data. We cannot use chmod to change the permissions because git
would consider it a local change of the files and would refuse to pull new revisions
before the local changes are committed. However, we can use the extended rights
management with access control lists (setfacl). The following scripts can be used
to clone the repositories.

clone_one.sh UD_Afrikaans
clone_all.sh
ud-treebank-list.txt # used by clone_all.sh

Note that the clone_one.sh script modifies default rights for newly created files
so that both the users 'www-data' and 'zeman' get full access. If the www-data
adds new files by git pull, I still want to be able to remove them when necessary.
If you are installing this infrastructure on your server, you probably want to
change 'zeman' to your username. And you may want to verify that the CGI scripts
indeed run as user 'www-data' on your system.

Similarly to the UD treebank folders, the repository tools must also be cloned
with complete access permissions for the users zeman and www-data. (But unlike
the treebank repositories, tools should stay in the master branch.)

Now we need a folder called log, lying in cgi/unidep next to the UD repositories,
with write access for user www-data:

mkdir log
setfacl -m u:www-data:rwx log

The main script that must be symlinked or copied to cgi/unidep is githook.pl.
This script will be invoked by a POST request from Github when a user pushes to
a UD repository. The URL of the script must be registered with the Universal-
Dependencies organization on Github:

https://github.com/organizations/UniversalDependencies/settings/hooks

Currently, the URL pointing to Dan's installation is

http://quest.ms.mff.cuni.cz/cgi-bin/zeman/unidep/githook.pl

Github shows a list of recent "payloads" sent to the githook script. If it shows
a red icon and a warning that the payload could not be delivered before timeout,
it does not necessarily mean that the process was really unsuccessful. We need
a lot of time to get the updated data and process them, and Apache will not send
the output of the githook script (i.e., our response to Github) before we are done.
Github may thus think that we are not responding despite everything being OK
at our end.

