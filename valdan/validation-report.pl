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
print("<p>Hover the mouse pointer over a treebank name to see validation summary.</p>\n");
my $nvalid = 0;
my $nerror = 0;
my $nempty = 0;
my $nstask = 0;
open(REPORT, "validation-report.txt") or die("Cannot read validation-report.txt: $!");
while(<REPORT>)
{
    s/\r?\n$//;
    my $color = 'black';
    if(m/ERROR/)
    {
        $color = 'red';
        $nerror++;
    }
    elsif(m/VALID/)
    {
        $color = 'green';
        $nvalid++;
        $nstask++ unless(m/not in shared task/);
    }
    elsif(m/EMPTY/)
    {
        $nempty++;
    }
    if(m/^(UD_.+?):/)
    {
        my $folder = $1;
        if(-e "log/$folder.log")
        {
            print("<span class='field-tip' style='color:$color'>$_<span class='tip-content'><pre>");
            print(`cat log/$folder.log`);
            print("</pre></span></span><br />\n");
        }
        else
        {
            print("<span style='color:$color'>$_</span><br />\n");
        }
    }
}
close(REPORT);
print("<hr />\n");
my $n = $nvalid + $nerror + $nempty;
print("Total $n, valid $nvalid ($nstask in shared task), error $nerror, empty $nempty.<br />\n");
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
<title>UD Validation Report</title>
<!-- from https://stackoverflow.com/questions/29485224/displaying-text-using-onmouseover-javascript-html -->
<style>
body {
    padding:30px;
    font:normal 12px/1.5 Arial, sans-serif;
}

/* Hover tooltips */
.field-tip {
    position:relative;
    cursor:help;
}
    .field-tip .tip-content {
        position:absolute;
        z-index:2; /* added by Dan; subsequent text lines might be longer than the current one, and we do not want them to appear above our tooltip */
        top:-22px; /* - top padding */
        right:9999px;
        width:800px;
        margin-right:-820px; /* width + left/right padding */
        padding:10px;
        color:#fff;
        background:#333;
        -webkit-box-shadow:2px 2px 5px #aaa;
           -moz-box-shadow:2px 2px 5px #aaa;
                box-shadow:2px 2px 5px #aaa;
        opacity:0;
        -webkit-transition:opacity 250ms ease-out;
           -moz-transition:opacity 250ms ease-out;
            -ms-transition:opacity 250ms ease-out;
             -o-transition:opacity 250ms ease-out;
                transition:opacity 250ms ease-out;
    }
        /* <http://css-tricks.com/snippets/css/css-triangle/> */
        .field-tip .tip-content:before {
            content:' '; /* Must have content to display */
            position:absolute;
            top:30px; /* was: 50% (to display in the middle of the frame) */
            left:-16px; /* 2 x border width */
            width:0;
            height:0;
            margin-top:-8px; /* - border width */
            border:8px solid transparent;
            border-right-color:#333;
        }
        .field-tip:hover .tip-content {
            right:-20px;
            opacity:1;
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
