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
my @files = grep {m/^feat_val\.[a-z]+$/ && -f "$tools/data/$_"} (readdir(DIR));
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
        # Filter out feature-value pairs that have a wrong form.
        if(!m/^[A-Z][A-Za-z0-9]*(\[[a-z]+\])?=[A-Z0-9][A-Za-z0-9]*$/)
        {
            next;
        }
        $data{$lcode}{$_}++;
        $n++;
    }
    close(FILE);
    if($n==0)
    {
        print STDERR ("WARNING: No valid feature values found in language '$lcode'\n");
    }
}
# Write JSON.
print("{\n");
my @lcodes = sort(keys(%data));
my @llines = ();
foreach my $lcode (@lcodes)
{
    if(!exists($lname_by_code{$lcode}))
    {
        print STDERR ("WARNING: Skipping unknown language code '$lcode'\n");
        next;
    }
    my $lline = '"'.escape_json_string($lcode).'": [';
    $lline .= join(', ', map {'"'.escape_json_string($_).'"'} (sort(keys(%{$data{$lcode}}))));
    $lline .= ']';
    push(@llines, $lline);
}
print(join(",\n", @llines)."\n");
print("}\n");



#------------------------------------------------------------------------------
# Takes a string and escapes characters that would prevent it from being used
# in JSON. (For control characters, it throws a fatal exception instead of
# escaping them because they should not occur in anything we export in this
# block.)
#------------------------------------------------------------------------------
sub escape_json_string
{
    my $string = shift;
    # https://www.ietf.org/rfc/rfc4627.txt
    # The only characters that must be escaped in JSON are the following:
    # \ " and control codes (anything less than U+0020)
    # Escapes can be written as \uXXXX where XXXX is UTF-16 code.
    # There are a few shortcuts, too: \\ \"
    $string =~ s/\\/\\\\/g; # escape \
    $string =~ s/"/\\"/g; # escape " # "
    if($string =~ m/[\x{00}-\x{1F}]/)
    {
        log_fatal("The string must not contain control characters.");
    }
    return $string;
}
