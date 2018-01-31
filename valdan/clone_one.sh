#!/bin/bash
# Usage: clone_one.sh UD_Uyghur

i=$1
rm -rf $i
git clone https://github.com/UniversalDependencies/$i.git
cd $i
git checkout dev
cd ..
# We must grant access permissions for the user www-data.
# We cannot do it using chmod because it would mean a local modification and git would refuse to pull.
# However, we can use access control lists (acl).
setfacl -R -m u:www-data:rwx $i
setfacl -R -d -m u:www-data:rwx $i
setfacl -R -d -m u:zeman:rwx $i
