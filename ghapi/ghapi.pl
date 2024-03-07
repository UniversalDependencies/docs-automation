#!/usr/bin/env perl
# Calls gh (GitHub command line interface) to access settings of a UD repository.
# Copyright © 2023 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# Prerequisity: Download and install gh (GitHub command line interface, https://cli.github.com/).
# I currently have it on my Windows laptop but not on the Linux network.
# Once it is installed (visible in PATH), populate the GH_TOKEN environment variable with my GitHub access token. Then run
#   gh auth login
# I am not sure how often I will have to call this. The credentials seem to stay valid for some time (I have not closed the command line window).
# Run gh --help to learn more. And visit https://docs.github.com/en/rest?apiVersion=2022-11-28 to learn about the API (gh api).

# gh repo create UniversalDependencies/UD_Tuwari-Autogramm --public --add-readme --team Contributors
###!!! It would be possible to add a "--clone" option to the above and immediately clone the new repository in one step.
###!!! But it will clone the repository using an https://-based URL while we may need a ssh://-based one (otherwise we may not be able to push).
###!!! So we better clone it separately, stating explicitly the ssh URL (set GIT_SSH==C:\Program Files\PuTTY\plink.exe may be needed first).
# git clone git@github.com:UniversalDependencies/UD_Tuwari-Autogramm.git
# cd UD_Tuwari-Autogramm
# copy ..\UD_ZZZ-Template\README.md .
# copy ..\UD_ZZZ-Template\CONTRIBUTING.md .
# copy ..\UD_ZZZ-Template\LICENSE.txt .
# git add CONTRIBUTING.md LICENSE.txt

# Manually edit the README.md (at least Contributors and Contact). When done, run the following:

# git commit -a -m "Initialization and the last commit to the master branch; switching to dev now."
# git checkout -b dev
# git push --all --set-upstream


# Use this command to get the JSON descriptions of all teams defined in the UniversalDependencies organization.
# gh api https://api.github.com/orgs/UniversalDependencies/teams
# It will tell us that the id of the Contributors team is 951065 and its URL is
# https://api.github.com/organizations/7457237/team/951065

# Something like this should grant the write permission for the Contributors team to the UD_Tuwari-Autogramm repository.
# https://api.github.com/teams/951065/repos/UniversalDependencies/UD_Tuwari-Autogramm
# PUT -d
# {"permission": "write"}

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use JSON::Parse 'parse_json';

sub usage
{
    print STDERR ("perl ghapi.pl --protect UD_Ancient_Greek-PROIEL\n");
    print STDERR ("    ... This will protect the master and dev branches of UD_Ancient_Greek-PROIEL the way we do it for UD treebank repositories.\n");
}

my $repo; # name of the repository to protect
GetOptions
(
    'protect=s' => \$repo
);
if(!defined($repo) || $repo !~ m/^UD_[-A-Za-z_]+$/)
{
    usage();
    die("Missing name of UD treebank repository to protect");
}

# Create JSON with protection settings for a 'master' branch.
# https://docs.github.com/en/rest/branches/branch-protection?apiVersion=2022-11-28#update-branch-protection
# enforce_admins=null ... the required status checks are not required for admins (otherwise I might have trouble when automatically merging dev into master)
# restrictions/empty sets of users, teams and apps means nobody will have push access except for owners and admins
# allow_force_pushes=false ... people cannot alter the commit history (which would be devastating for the validator and for other users)
# allow_deletions=false ... people cannot delete the branch
my $master_protection_json = <<EOF
{
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "required_status_checks": null,
  "restrictions": {
    "users": [],
    "teams": [],
    "apps": []
  },
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
;
my $dev_protection_json = <<EOF
{
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "required_status_checks": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
;

protect_branch($repo, 'master');
protect_branch($repo, 'dev');

# We could obtain the list of known repositories and protect them all.
# But now this script is intended to protect one particular repository
# whose name was given as the --protect option.
#print STDERR ("Fetching the list of UD treebank repositories from Github...\n");
#my @repos = list_treebank_repos();
#my $n = scalar(@repos);
#my $npriv = scalar(grep {$_->{visibility} eq 'private'} (@repos));
#print STDERR ("Found $n repositories ($npriv private).\n");
# Protect dev branches of all repos.
#foreach my $repo (@repos)
#{
#    print STDERR ("Test: Protect branch dev of $repo->{name}...\n");
#    protect_branch($repo->{name}, 'dev');
#}



#------------------------------------------------------------------------------
# Uses Github API to obtain the list of repositories owned by Universal
# Dependencies.
#------------------------------------------------------------------------------
sub list_treebank_repos
{
    my $uri = 'orgs/UniversalDependencies/repos?per_page=100';
    my @repos = ();
    my $page = 1;
    while(1)
    {
        my $response = ghapi("$uri&page=$page");
        die("Expected array") if(ref($response) ne 'ARRAY');
        my $n = scalar(@{$response});
        last if($n == 0);
        push(@repos, @{$response});
        $page++;
    }
    @repos = sort {$a->{name} cmp $b->{name}} (grep {$_->{name} =~ m/^UD_[A-Z][A-Za-z_]+-[A-Z][A-Za-z]+$/} (@repos));
    return @repos;
}



#------------------------------------------------------------------------------
# Protects 'master' or 'dev' branch.
#------------------------------------------------------------------------------
sub protect_branch
{
    my $repo = shift;
    my $branch = shift;
    die if($repo !~ m/^UD_[A-Z][A-Za-z_]+-[A-Z][A-Za-z]+$/);
    die if($branch !~ m/^(master|dev)$/);
    my $json = $branch eq 'master' ? $master_protection_json : $dev_protection_json;
    # Save the JSON to a file where gh will find it. This way we avoid headache
    # with escaping JSON on the command line.
    my $json_file_name = "branch_protection-$$.json";
    if(-f $json_file_name)
    {
        die("File '$json_file_name' already exists");
    }
    open(JSON, ">$json_file_name") or die("Cannot write $json_file_name: $!");
    print JSON ($json);
    close(JSON);
    my $apicall = "repos/UniversalDependencies/$repo/branches/$branch/protection -X PUT --input $json_file_name";
    my $response = ghapi($apicall);
    ###!!! Debugging: Print the resulting setting of allow_force_pushes.
    print STDERR ("allow_force_pushes = '$response->{allow_force_pushes}{enabled}'\n");
    unlink($json_file_name) or die("Cannot remove $json_file_name: $!");
}



#------------------------------------------------------------------------------
# Uses system(gh) to communicate with the GitHub REST API.
#------------------------------------------------------------------------------
sub ghapi
{
    my $apicall = shift;
    return parse_json(`gh api $apicall`);
}
