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

my @folders = list_ud_folders();
open(REPORT, ">validation-report.txt") or die("Cannot write validation-report.txt: $!");
system("cp validation-report.txt old-validation-report.txt");
system("echo -n '' > validation-report.txt");
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
