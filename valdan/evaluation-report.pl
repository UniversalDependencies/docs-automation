#!/usr/bin/env perl
# Reads the validation report and presents it as a HTML page.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

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
foreach my $folder (@folders)
{
    my $starsid = sprintf("stars%02d", $hash{$folder}{stars}*10);
    print("<img id=\"$starsid\" src=\"http://universaldependencies.org/img/img_trans.gif\" /> $folder $hash{$folder}{score} $hash{$folder}{stars}<br />\n");
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
