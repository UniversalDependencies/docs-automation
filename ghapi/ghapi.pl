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
use Carp;
use Getopt::Long;
use JSON::Parse 'parse_json';

sub usage
{
    print STDERR ("perl ghapi.pl --create UD_Ancient_Greek-PROIEL\n");
    print STDERR ("    ... This will create treebank repository UD_Ancient_Greek-PROIEL, clone it and initialize up to the point where README.md should be edited manually.\n");
    print STDERR ("perl ghapi.pl --finalize UD_Ancient_Greek-PROIEL\n");
    print STDERR ("    ... This will finalize the creation of the treebank repository UD_Ancient_Greek-PROIEL after README.md has been edited manually (finalization includes protection).\n");
    print STDERR ("perl ghapi.pl --protect UD_Ancient_Greek-PROIEL\n");
    print STDERR ("    ... This will protect the master and dev branches of UD_Ancient_Greek-PROIEL the way we do it for UD treebank repositories.\n");
}

my $create_repo; # name of the repository to create
my $finalize_repo; # name of the repository to finalize (including protection)
my $protect_repo; # name of the repository to protect
GetOptions
(
    'create=s'   => \$create_repo,
    'finalize=s' => \$finalize_repo,
    'protect=s'  => \$protect_repo
);
my $create = defined($create_repo) && $create_repo =~ m/^UD_[-A-Za-z_]+$/;
my $finalize = defined($finalize_repo) && $finalize_repo =~ m/^UD_[-A-Za-z_]+$/;
my $protect = defined($protect_repo) && $protect_repo =~ m/^UD_[-A-Za-z_]+$/;
if($create && $protect || $finalize && $protect || $create && $finalize)
{
    usage();
    confess("Cannot create, finalize and protect at the same time");
}
if(!$create && !$finalize && !$protect)
{
    usage();
    confess("Need a repository name to either create or finalize or protect");
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

if($create)
{
    create_repository($create_repo);
}
elsif($finalize)
{
    finalize_repository($finalize_repo);
}
elsif($protect)
{
    protect_branch($protect_repo, 'master');
    protect_branch($protect_repo, 'dev');
}

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
# Creates a UD treebank repository, clones it to the local disk and performs
# the initialization up to the point where README.md must be edited manually.
# Requires gh and git (with credentials for Github).
#------------------------------------------------------------------------------
sub create_repository
{
    my $repo = shift;
    confess("Wrong repo name '$repo'") unless($repo =~ m/^UD_[-A-Za-z_]+$/);
    saferun("gh repo create UniversalDependencies/$repo --public --add-readme --team Contributors") or confess();
    saferun("git clone git\@github.com:UniversalDependencies/$repo.git") or confess();
    chdir($repo) or confess("Cannot change to folder '$repo': $!");
    copy_file('../UD_ZZZ-Template/README.md', './README.md');
    copy_file('../UD_ZZZ-Template/CONTRIBUTING.md', './CONTRIBUTING.md');
    copy_file('../UD_ZZZ-Template/LICENSE.txt', './LICENSE.txt');
    saferun("git add CONTRIBUTING.md LICENSE.txt") or confess();
}



#------------------------------------------------------------------------------
# Finalizes the creation of a new treebank repository after the README.md file
# has been edited (typically we need to modify at least Contributors and
# Contact).
#------------------------------------------------------------------------------
sub finalize_repository
{
    my $repo = shift;
    confess("Wrong repo name '$repo'") unless($repo =~ m/^UD_[-A-Za-z_]+$/);
    chdir($repo) or confess("Cannot change to folder '$repo': $!");
    saferun('git commit -a -m "Initialization and the last commit to the master branch; switching to dev now."') or confess();
    saferun('git checkout -b dev') or confess();
    saferun('git push --all --set-upstream') or confess();
    protect_branch($repo, 'master');
    protect_branch($repo, 'dev');
}



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
    #print STDERR ("allow_force_pushes = '$response->{allow_force_pushes}{enabled}'\n");
    unlink($json_file_name) or confess("Cannot remove $json_file_name: $!");
}



#------------------------------------------------------------------------------
# Uses system(gh) to communicate with the GitHub REST API.
#------------------------------------------------------------------------------
sub ghapi
{
    my $apicall = shift;
    print STDERR ("Executing in shell: gh api $apicall\n");
    return parse_json(`gh api $apicall`);
}



#------------------------------------------------------------------------------
# Copies a text file. We use Perl input/output functions to avoid shell-
# specific commands.
#------------------------------------------------------------------------------
sub copy_file
{
    my $inpath = shift;
    my $outpath = shift;
    confess("Unknown input file") if(!defined($inpath));
    confess("Unknown output file") if(!defined($outpath));
    # Open the file for writing with :raw layer to disable line-ending translation
    # (LF should not be translated to CRLF on Windows). Consequently, open the
    # input file with :raw as well to prevent "wide character in print" complaints.
    open(IN, '<:raw', $inpath) or confess("Cannot read '$inpath': $!");
    open(OUT, '>:raw', $outpath) or confess("Cannot write '$outpath': $!");
    while(<IN>)
    {
        $_ =~ s/\r?\n$//;
        $_ .= "\n";
        print OUT;
    }
}



#------------------------------------------------------------------------------
# Calls an external program. Uses system(). In addition, echoes the command
# line to the standard error output, and returns true/false according to
# whether the call was successful and the external program returned 0 (success)
# or non-zero (error).
#
# Typically called as follows:
#     saferun($command) or die;
#------------------------------------------------------------------------------
sub saferun
{
    my $command = join(' ', @_);
    print STDERR ("Executing in shell: $command\n");
    # bash may not be available
    #system('bash', '-c', $command);
    system($command);
    # The external program does not exist, is not executable or the execution failed for other reasons.
    if($?==-1)
    {
        die("ERROR: Failed to execute: $command\n  $!\n");
    }
    # We were able to start the external program but its execution failed.
    elsif($? & 127)
    {
        printf STDERR ("ERROR: Execution of: $command\n  died with signal %d, %s coredump\n",
            ($? & 127), ($? & 128) ? 'with' : 'without');
        die;
    }
    # The external program ended "successfully" (this still does not guarantee
    # that the external program returned zero!)
    else
    {
        my $exitcode = $? >> 8;
        print STDERR ("Exit code: $exitcode\n") if($exitcode);
        # Return false if the program returned a non-zero value.
        # It is up to the caller how they will handle the return value.
        # (The easiest is to always write:
        # saferun($command) or die;
        # )
        return ! $exitcode;
    }
}
