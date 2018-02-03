#!/usr/bin/env perl
# Checks whether a test file is suitable for the shared task:
# - at least 10000 words
# - the most frequent word is not '_' (non-free treebanks)
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $n = 0;
my %lex;
while(<>)
{
    if(m/^\d+\t([^\t]+)/)
    {
        $n++;
        $lex{$1}++;
    }
}
my @keys = sort {$lex{$b} <=> $lex{$a}} (keys(%lex));
if($keys[0] eq '_')
{
    print("not in shared task: missing underlying text\n");
    exit(1);
}
elsif($n < 10000)
{
    print("not in shared task: test data too small\n");
    exit(2);
}
exit(0);
