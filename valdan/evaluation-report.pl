#!/usr/bin/env perl
# Reads the validation report and presents it as a HTML page.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
# Install JSON::Parse and YAML locally to the following folder.
# (Assuming they are not available system-wide on the web server, and we only have permissions to install locally.)
use lib 'perllib/lib/perl5';
use lib 'tools';
use udlib;

my $lhash = udlib::get_language_hash();

vypsat_html_zacatek();
my %hash;
open(REPORT, "evaluation-report.txt") or die("Cannot read validation-report.txt: $!");
while(<REPORT>)
{
    s/\r?\n$//;
    my ($folder, $score, $stars) = split(/\t/, $_);
    $hash{$folder}{score} = $score;
    $hash{$folder}{stars} = $stars;
}
close(REPORT);
my @folders = keys(%hash);
@folders = sort
{
    my $result = $hash{$b}{score} <=> $hash{$a}{score};
    unless($result)
    {
        $result = $a cmp $b;
    }
    $result;
}
(@folders);
# If we want to group treebanks by languages, we need a list of winners per language.
my @winners;
my %map;
foreach my $folder (@folders)
{
    my $language;
    if($folder =~ m/^UD_(.+?)(-|$)/)
    {
        $language = $1;
    }
    if(!exists($map{$language}))
    {
        push(@winners, $folder);
        $map{$language}++;
    }
}
foreach my $winner (@winners)
{
    my $language;
    my $flagcode;
    if($winner =~ m/^UD_(.+?)(-|$)/)
    {
        $language = $1;
    }
    my $language_no_underscores = $language;
    $language_no_underscores =~ s/_/ /g;
    if(exists($lhash->{$language_no_underscores}))
    {
        $flagcode = $lhash->{$language_no_underscores}{flag};
    }
    foreach my $folder (@folders)
    {
        if($folder =~ m/^UD_$language(-|$)/)
        {
            my $starsid = sprintf("stars%02d", $hash{$folder}{stars}*10);
            my $flag = '';
            if(defined($flagcode))
            {
                $flag = '<img width="32" src="http://universaldependencies.org/flags/svg/'.$flagcode.'.svg" style="border:1px solid grey;" />';
            }
            print("<img id=\"$starsid\" src=\"http://universaldependencies.org/img/img_trans.gif\" /> $flag $folder $hash{$folder}{score} $hash{$folder}{stars}<br />\n");
        }
    }
}
vypsat_html_konec();



#------------------------------------------------------------------------------
# Vypíše záhlaví MIME a začátek potvrzovací stránky.
#------------------------------------------------------------------------------
sub vypsat_html_zacatek
{
    print <<EOF
Content-type: text/html; charset=utf-8

<html xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>UD Evaluation Report</title>
<link rel="icon" href="https://universaldependencies.org/logos/logo-ud.png" type="image/png">
<!-- from https://stackoverflow.com/questions/29485224/displaying-text-using-onmouseover-javascript-html -->
<style>
#stars00 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 0;
}

#stars05 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -32px;
}

#stars10 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -64px;
}

#stars15 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -96px;
}

#stars20 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -128px;
}

#stars25 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -160px;
}

#stars30 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -192px;
}

#stars35 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -224px;
}

#stars40 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -256px;
}

#stars45 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -288px;
}

#stars50 {
    width: 160px;
    height: 32px;
    background: url(http://universaldependencies.org/img/stars.png) 0 -320px;
}
</style>
</head>
<body>
EOF
    ;
}



#------------------------------------------------------------------------------
# Vypíše konec potvrzovací stránky.
#------------------------------------------------------------------------------
sub vypsat_html_konec
{
    # Odeslat volajícímu konec webové stránky s odpovědí.
    print <<EOF
</body>
</html>
EOF
    ;
}
