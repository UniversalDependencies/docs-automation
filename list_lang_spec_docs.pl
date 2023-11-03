#!/usr/bin/env perl
# Generates the list of links to language-specific UD guidelines.
# Copyright © 2023 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use YAML qw(LoadFile);
use Getopt::Long;

my $langyaml = 'codes_and_flags.yaml'; # provide path on command line if not in current folder
my $docspath = '../docs';
GetOptions
(
    'codes=s'    => \$langyaml,
    'docs-dir=s' => \$docspath
);

if(! -f $langyaml)
{
    die("Cannot find file '$langyaml'");
}
if(! -d $docspath)
{
    die("Cannot find folder '$docspath'");
}
my $languages = LoadFile($langyaml);
# The $languages hash is indexed by language names. Create a mapping from families and genera.
my %fglanguages;
foreach my $lname (keys(%{$languages}))
{
    # We are only interested in languages that already have some documentation.
    my $langdoc = "$docspath/_$languages->{$lname}{lcode}/index.md";
    next if(! -f $langdoc);
    my $family_genus = $languages->{$lname}{family};
    if($family_genus =~ m/^(.+),\s*(.+)$/)
    {
        $languages->{$lname}{familygenus} = $family_genus;
        $languages->{$lname}{family} = $1;
        $languages->{$lname}{genus} = $2;
    }
    else
    {
        $languages->{$lname}{familygenus} = $family_genus;
        $languages->{$lname}{genus} = '';
    }
    $languages->{$lname}{family} = 'Indo-European' if($languages->{$lname}{family} eq 'IE');
    $fglanguages{$languages->{$lname}{family}}{$languages->{$lname}{genus}}{$lname} = $languages->{$lname};
}
# Print the links organized by family and genus.
foreach my $f (sort(keys(%fglanguages)))
{
    print("<h2>$f</h2>\n");
    my @genera = sort(keys(%{$fglanguages{$f}}));
    foreach my $g (@genera)
    {
        # Only print genus headings if there are multiple genera.
        if(scalar(@genera) > 1)
        {
            print("<h3>$g</h3>\n");
        }
        # Style: no bullets, there will be flags instead.
        print("<ul style=\"list-style-type: none; padding: 0\">\n");
        foreach my $l (sort(keys(%{$fglanguages{$f}{$g}})))
        {
            # We want to define the following style in CSS:
            # img.flag { vertical-align: middle; border: solid grey 1px; height: 1em; }
            # However, more styles are needed to make the text left-aligned while keeping the aspect ratio of the flags.
            # <li> padding-left: 55px makes sure the text starts after even the widest flag.
            # <img> absolute position left: 0 makes sure the flag ignores the padding (but the absolute position is still relative with respect to <li>).
            # <li> could also have line-height: 1.5;
            print("  <li style=\"display: flex; align-items: center; position: relative; padding-left: 55px\"><img class=\"flag\" style=\"position: absolute; left: 0\" src=\"/flags/png/$fglanguages{$f}{$g}{$l}{flag}.png\"><a href=\"/$fglanguages{$f}{$g}{$l}{lcode}/index.html\">$l</a></li>\n");
        }
        print("</ul>\n");
    }
}
