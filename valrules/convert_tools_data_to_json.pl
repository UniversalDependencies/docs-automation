#!/usr/bin/env perl
# Jednorázový skript, který převede validační data do JSONu.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use YAML qw(LoadFile);
require valdata;

my $ud = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies';
my $tools = "$ud/tools";
my $codes_and_flags = "$ud/docs-automation/codes_and_flags.yaml";
# Read the list of known languages.
my $languages = LoadFile($codes_and_flags);
if ( !defined($languages) )
{
    die "Cannot read the list of languages";
}
# The $languages hash is indexed by language names. Create a mapping from language codes.
# At the same time, separate family from genus where applicable.
my %lname_by_code; map {$lname_by_code{$languages->{$_}{lcode}} = $_} (keys(%{$languages}));
opendir(DIR, "$tools/data") or die("Cannot read folder '$tools/data': $!");
my @files = grep {m/^deprel\.[a-z]+$/ && -f "$tools/data/$_"} (readdir(DIR));
closedir(DIR);
print STDERR ("Found ".scalar(@files)." files: ".join(', ', @files)."\n");
my %data;
foreach my $file (@files)
{
    my $lcode;
    if($file =~ m/\.([a-z]+)$/)
    {
        $lcode = $1;
    }
    else
    {
        die("Cannot detect language code of file '$file'");
    }
    my $n = 0;
    open(FILE, "$tools/data/$file") or die("Cannot read file '$tools/data/$file': $!");
    while(<FILE>)
    {
        chomp();
        s/\#.*//;
        # Filter out dependency relations that have a wrong form.
        if(!m/^[a-z]+(:[a-z]+)?$/)
        {
            next;
        }
        $data{$lcode}{$_} = {'type' => 'lspec', 'permitted' => 1};
        $n++;
    }
    close(FILE);
    if($n==0)
    {
        print STDERR ("WARNING: No valid dependency relations found in language '$lcode'\n");
    }
}
valdata::write_deprels_json(\%data, 'deprels.json');
