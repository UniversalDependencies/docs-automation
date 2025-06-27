#!/usr/bin/env perl
# Validates CoNLL-U files in all UD repositories. If a list of language codes
# is supplied as arguments, validates only repositories of the given languages.
# Updates validation-report.txt and creates a new log/UD_*.log for every
# treebank (this file is used in the web report, too).
# Copyright © 2018, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Cwd; # getcwd()
use YAML qw(LoadFile);

my @folders = list_ud_folders();
my $nlang = scalar(@ARGV);
if($nlang > 0)
{
    print('Languages: '.join(' ', @ARGV)."\n");
    print("Validating treebanks of $nlang languages.\n");
    my %lcodes_to_validate;
    foreach my $lcode (@ARGV)
    {
        $lcodes_to_validate{$lcode}++;
    }
    # Read the database of languages (we need a mapping between codes and names).
    # Temporarily go to the folder of the script (if we are not already there).
    my $currentpath = getcwd();
    my $scriptpath = $0;
    if($scriptpath =~ m:/:)
    {
        $scriptpath =~ s:/[^/]*$:/:;
        chdir($scriptpath) or die("Cannot go to folder '$scriptpath': $!");
    }
    my $languages_by_name = LoadFile('../codes_and_flags.yaml');
    chdir($currentpath);
    # Filter the UD folders. Keep only treebanks of required languages.
    my @filtered;
    foreach my $folder (@folders)
    {
        my $lname = $folder;
        $lname =~ s/^UD_//;
        $lname =~ s/-.*//;
        $lname =~ s/_/ /g;
        my $lcode = $languages_by_name->{$lname}{lcode};
        if($lcodes_to_validate{$lcode})
        {
            push(@filtered, $folder);
        }
    }
    my $ntotal = scalar(@folders);
    my $nfiltered = scalar(@filtered);
    print("$nfiltered out of $ntotal treebanks will be validated.\n");
    @folders = @filtered;
}
else
{
    print("Validating treebanks of all languages.\n");
}
my $n = scalar(@folders);
#for(my $i = 1; $i <= $n; $i++)
#{
#    my $folder = $folders[$i-1];
#    print("$folder ($i/$n)\n");
#    system("perl update-validation-report.pl $folder");
#}
my $folders_to_validate = join(' ', @folders);
system("perl queue_validate.pl $folders_to_validate");



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
