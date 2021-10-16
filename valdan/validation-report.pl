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

vypsat_html_zacatek();
my $timer = get_timer('November 1, 2021 23:59:59');
print("<h1>Universal Dependencies Validation Report ($timer)</h1>\n");
print(get_explanation());
#print("<p>Hover the mouse pointer over a treebank name to see validation summary. Click on the “report” link to see the full output of the validation software.</p>\n");
print("<p>Click on the “report” link to see the full output of the validation software.</p>\n");
print("<hr />\n");
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
    # If a legacy treebank has an exception that is no longer needed, the line will end with UNEXCEPT and a list of error ids.
    # We should modify the message so that it does not confuse the data maintainers. We also should not format this message
    # like we format the main result.
    my $unexcept = '';
    if(s/UNEXCEPT\s*(.*)//)
    {
        $unexcept = " <span style='color:gray'>The following legacy exceptions are no longer needed: $1</span>";
    }
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
            if(s/(ERROR; DISCARD|ERROR; BACKUP \d+\.\d+|LEGACY(?:; \d+-\d+-\d+)?)(\s*\(.+?\))/$1/)
            {
                $errorlist = $2;
            }
            if(m/(ERROR; DISCARD|ERROR; BACKUP \d+\.\d+|LEGACY(; \d+-\d+-\d+)?)/)
            {
                $reportlink = " (<a href=\"validation-report.pl?$folder\">report</a>)";
            }
            ###!!! 2020-11-29: DZ: Turning off the field tips. They are too long now that most treebanks are red. And sometimes it is not possible to click on the "report" link because of mad field tips jumping around.
            if(0)
            {
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
                $html .= "</pre></span></span>$errorlist$reportlink$unexcept<br />\n";
            }
            else # no field tips
            {
                $html .= "<span style='color:$color;font-weight:bold'>$_</span>$errorlist$reportlink$unexcept<br />\n";
            }
        }
        else
        {
            $html .= "<span style='color:$color;font-weight:bold'>$_</span>$unexcept<br />\n";
        }
        print($html);
    }
}
close(REPORT);
print("<hr />\n");
my $n = $nvalid + $nlegacy + $nerror + $nempty;
my $nlvalid = scalar(keys(%languages_valid));
my $nltotal = scalar(keys(%languages));
my $nlerror = $nltotal-$nlvalid;
print("Total $n, valid $nvalid, legacy $nlegacy, error $nerror, empty $nempty.<br />\n");
print("Total $nltotal languages, valid/legacy $nlvalid, error/empty $nlerror.<br />\n");
vypsat_html_konec();



#------------------------------------------------------------------------------
# Generates explanatory text.
#------------------------------------------------------------------------------
sub get_explanation
{
    my $text = <<EOF
    <p>This is the output of automatic on-line validation of UD data.
    Besides the official UD validation script, <tt>validate.py</tt>,
    it also runs <tt>check_files.pl</tt> to make sure that each treebank
    repository contains the expected files with expected names.
    All tests are conducted in the <tt>dev</tt> branch of the respective
    repository, and they are rerun each time the contents of the branch is
    modified. They are also rerun whenever the validation software changes.</p>

    <p>The report on this page is an important indicator whether the current
    contents of the <tt>dev</tt> branch can be released when the release time
    comes. The treebanks with the green <span style='color:green;font-weight:bold'>VALID</span>
    label are fine and ready to go. The purple <span style='color:purple;font-weight:bold'>LEGACY</span>
    treebanks are not fine but we can still release them. They were considered
    valid at the time of a previous release and the only errors that are reported
    now are based on new tests that were not available when the treebank was
    approved. Finally, if a treebank has the red <span style='color:red;font-weight:bold'>ERROR</span>
    label, it cannot be released in this state. Either the treebank is new and
    does not pass all currently available tests, or the treebank is not new
    but new types of errors were introduced in it. New treebanks will only be
    released when they are completely valid. If an old treebank contains new
    errors, we will re-release its previous version and ignore the <tt>dev</tt>
    branch.</p>

    <p>See the <a href="https://universaldependencies.org/release_checklist.html">release
    checklist</a> for more information on treebank requirements and validation.</p>
EOF
    ;
    return $text;
}



#------------------------------------------------------------------------------
# Generates countdown timer (from https://www.w3schools.com/howto/howto_js_countdown.asp)
#------------------------------------------------------------------------------
sub get_timer
{
    my $deadline = shift; # "Jan 5, 2021 15:37:25"
    my $text = <<EOF
data freeze in: <span id="timer"></span><script>
// Set the date we're counting down to
var countDownDate = new Date("$deadline").getTime();

// Update the count down every 1 second
var x = setInterval(function() {

  // Get today's date and time
  var now = new Date().getTime();

  // Find the distance between now and the count down date
  var distance = countDownDate - now;

  // Time calculations for days, hours, minutes and seconds
  var days = Math.floor(distance / (1000 * 60 * 60 * 24));
  var hours = Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  var minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
  var seconds = Math.floor((distance % (1000 * 60)) / 1000);

  // Output the result in an element with id="timer"
  document.getElementById("timer").innerHTML = days + "d " + hours + "h "
  + minutes + "m " + seconds + "s";

  // If the count down is over, write some text
  if (distance < 0) {
    clearInterval(x);
    document.getElementById("timer").innerHTML = "FROZEN NOW";
  }
}, 1000);
</script>
EOF
    ;
    $text =~ s/\s+$//s;
    return $text;
}



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
