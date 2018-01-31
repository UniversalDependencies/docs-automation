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

