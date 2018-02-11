#!/usr/bin/env perl
# Updates the evaluation report line of a particular treebank.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');



my $folder = $ARGV[0];
exit if(!defined($folder));
$folder =~ s:/$::;
$folder =~ s:^\./::;
system("cd $folder ; git pull --no-edit ; cd ..");
system("date > log/$folder.eval.log 2>&1");
my $command = "perl -I perllib/lib/perl5 -I tools tools/evaluate_treebank.pl --verbose $folder";
system("echo $command >> log/$folder.eval.log");
system("$command >> log/$folder.eval.log 2>&1");
my $treebank_message = `grep $folder log/$folder.eval.log | tail -1`;
$treebank_message =~ s/\r?\n$//;
print STDERR ("$treebank_message\n");
# Update the evaluation report that comprises all treebanks.
my %evalreps;
open(REPORT, "evaluation-report.txt");
while(<REPORT>)
{
    s/\r?\n$//;
    if(m/^(UD_.+?)\t/)
    {
        $evalreps{$1} = $_;
    }
}
close(REPORT);
$evalreps{$folder} = $treebank_message;
my @treebanks = sort(keys(%evalreps));
###!!! This is still not safe enough! If two processes try to modify the file at the same time, it can get corrupt!
system("cp evaluation-report.txt evaluation-report.bak");
open(REPORT, ">evaluation-report.txt");
foreach my $treebank (@treebanks)
{
    print REPORT ("$evalreps{$treebank}\n");
}
close(REPORT);
