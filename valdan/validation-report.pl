#!/usr/bin/env perl
# Reads the validation report and presents it as a HTML page.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# The client may want to get just the information rather than a fancy report.
if($ENV{QUERY_STRING} =~ m/text_only/)
{
    print("Content-type: text/plain\n\n");
    open(REPORT, "validation-report.txt") or die("Cannot read validation-report.txt: $!");
    while(<REPORT>)
    {
        print;
    }
    close(REPORT);
    exit();
}
# We may be also asked for the validation log of a particular treebank.
elsif($ENV{QUERY_STRING} =~ m/(UD_[A-Za-z_]+-[A-Za-z]+)/ && -f "log/$1.log")
{
    print("Content-type: text/plain; charset=utf-8\n\n");
    open(REPORT, "log/$1.log") or die("Cannot read log/$1.log: $!");
    while(<REPORT>)
    {
        print;
    }
    close(REPORT);
    exit();
}

###!!! Temporarily, I want to see shared task treebanks first, then the rest.
my $shared_task_first = 0;
my $deferred;

vypsat_html_zacatek();
print("<p>Hover the mouse pointer over a treebank name to see validation summary.</p>\n");
my $nvalid = 0;
my $nlegacy = 0;
my $nerror = 0;
my $nempty = 0;
my %languages;
my %languages_valid;
open(REPORT, "validation-report.txt") or die("Cannot read validation-report.txt: $!");
while(<REPORT>)
{
    s/\r?\n$//;
    my $language = $_;
    $language =~ s/:.*//;
    $language =~ s/-.*//;
    $language =~ s/^UD_//;
    $language =~ s/_/ /g;
    my $color = 'black';
    if(m/ERROR/)
    {
        $color = 'red';
        $nerror++;
    }
    elsif(m/LEGACY/)
    {
        $color = 'purple';
        $nlegacy++;
        $languages_valid{$language}++;
    }
    elsif(m/VALID/)
    {
        $color = 'green';
        $nvalid++;
        $languages_valid{$language}++;
    }
    elsif(m/EMPTY/)
    {
        $nempty++;
    }
    if(m/^(UD_.+?):/)
    {
        my $folder = $1;
        $languages{$language}++;
        my $html;
        if(-e "log/$folder.log")
        {
            my $errorlist = '';
            my $reportlink = '';
            if(s/(ERROR; DISCARD|ERROR; BACKUP \d+\.\d+|LEGACY)(\s*\(.+?\))/$1/)
            {
                $errorlist = $2;
            }
            if(m/(ERROR; DISCARD|ERROR; BACKUP \d+\.\d+|LEGACY)/)
            {
                $reportlink = " (<a href=\"validation-report.pl?$folder\">report</a>)";
            }
            $html .= "<span class='field-tip' style='color:$color;font-weight:bold'>$_<span class='tip-content'><pre>";
            my $log = `cat log/$folder.log`;
            # Only show the beginning of the log here.
            my @lines = split(/\n/, $log);
            my $n = 20;
            if(scalar(@lines) > $n)
            {
                splice(@lines, $n);
                push(@lines, '...');
                push(@lines, 'Follow the report link to see the full validation report.');
                $log = join("\n", @lines)."\n";
            }
            $html .= zneskodnit_html($log);
            $html .= "</pre></span></span>$errorlist$reportlink<br />\n";
        }
        else
        {
            $html .= "<span style='color:$color;font-weight:bold'>$_</span><br />\n";
        }
        print($html);
    }
}
close(REPORT);
if($shared_task_first && defined($deferred))
{
    print("<hr />\n");
    print($deferred);
}
print("<hr />\n");
my $n = $nvalid + $nlegacy + $nerror + $nempty;
my $nlvalid = scalar(keys(%languages_valid));
my $nltotal = scalar(keys(%languages));
my $nlerror = $nltotal-$nlvalid;
print("Total $n, valid $nvalid, legacy $nlegacy, error $nerror, empty $nempty.<br />\n");
print("Total $nltotal languages, valid/legacy $nlvalid, error/empty $nlerror.<br />\n");
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



#------------------------------------------------------------------------------
# V textu zneškodní znaky, které mají zvláštní význam v HTML.
#------------------------------------------------------------------------------
sub zneskodnit_html
{
    my $text = shift;
    $text =~ s/&/&amp;/sg;
    $text =~ s/"/&quot;/sg; #"
    $text =~ s/</&lt;/sg;
    $text =~ s/>/&gt;/sg;
    return $text;
}
