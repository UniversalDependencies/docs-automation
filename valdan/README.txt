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
 
