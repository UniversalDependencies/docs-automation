#This will last us to 300 repositories
(for pg in 1 2 3; do wget "https://api.github.com/orgs/UniversalDependencies/repos?page=$pg&per_page=100" -O - ; done ) | grep git_url | grep -Po 'git://.*?(?=")' > all_repos.txt

echo "Missing languages"
echo "cd UD-dev-branches"
M=""
for r in $(cat all_repos.txt)
do
    l=$(echo $r | perl -pe 's/.*\///' | cut -f 1 -d.)
    if [[ ! -e UD-dev-branches/$l ]] && [[ $l == UD_* ]] && [[ $l != UD_v2 ]]
    then
	echo "git clone -b dev $r"
	M="$M UD-dev-branches/$l"
    fi
done
echo $M
