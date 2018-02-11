#!/usr/bin/env perl
# Validates CoNLL-U files in all UD repositories.
# Creates new validation-report.txt, and new log/UD_*.log for every treebank (this is used in the web report, too).
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# The script evaluate_treebank.pl needs udlib, which in turn needs JSON::Parse
# and YAML. If we are running on a server where these modules are not installed
# globally (e.g., quest.ms.mff.cuni.cz), we can install them using cpanm to a
# local folder 'perllib'.
my $include = '';
if(-d 'perllib/lib/perl5')
{
    $include = '-I perllib/lib/perl5';
}
my @folders = list_ud_folders();
foreach my $folder (@folders)
{
    print("$folder\n");
    system("perl update-validation-report.pl $folder");
}



#==============================================================================
# The following functions are available in tools/udlib.pm. However, udlib uses
# JSON::Parse, which is not installed on quest, so we cannot use it here.
#==============================================================================



#------------------------------------------------------------------------------
# Returns list of UD_* folders in a given folder. Default: the current folder.
#------------------------------------------------------------------------------
sub list_ud_folders
{
    my $path = shift;
    $path = '.' if(!defined($path));
    opendir(DIR, $path) or die("Cannot read the contents of '$path': $!");
    my @folders = sort(grep {-d "$path/$_" && m/^UD_.+/} (readdir(DIR)));
    closedir(DIR);
    return @folders;
}
