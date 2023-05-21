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
        print("<ul>\n");
        foreach my $l (sort(keys(%{$fglanguages{$f}{$g}})))
        {
            # We want to define the following style in CSS:
            # img.flag { vertical-align: middle; border: solid grey 1px; height: 1em; }
            print("  <li><img class=\"flag\" src=\"/flags/png/$fglanguages{$f}{$g}{$l}{flag}.png\"><a href=\"/$fglanguages{$f}{$g}{$l}{lcode}/index.html\">$l</a></li>\n");
        }
        print("</ul>\n");
    }
}
