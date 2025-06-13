#!/usr/bin/perl -wT

use strict;
use utf8;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use YAML qw(LoadFile);
#binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use open ':utf8';
use Encode;
use charnames ();
# We need to tell Perl where to find my Perl modules. We could make it relative
# to the location of the script but we would have to take care for untainting
# all path info from the operating system. Since this is a CGI script intended
# to run at just one web server (currently https://quest.ms.mff.cuni.cz/udvalidator/),
# hard-wiring the absolute path is a reasonable option (we will also need it to
# access the data).
my $path; BEGIN {$path = '/usr/lib/cgi-bin/unidep/docs-automation/valrules';}
use lib $path;
use common;
use valdata;
use langgraph;

# Read the list of known languages.
my $languages = LoadFile($path.'/../codes_and_flags.yaml');
if(!defined($languages))
{
    die("Cannot read the list of languages");
}
# The $languages hash is indexed by language names. Create a mapping from language codes.
# At the same time, separate family from genus where applicable.
my %lname_by_code; map {$lname_by_code{$languages->{$_}{lcode}} = $_} (keys(%{$languages}));
foreach my $lname (keys(%{$languages}))
{
    $lname_by_code{$languages->{$lname}{lcode}} = $lname;
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
}
# We must set our own PATH even if we do not depend on it.
# The system call may potentially use it, and the one from outside is considered insecure.
$ENV{'PATH'} = $path.':/home/zeman/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
# Print the output.
my $query = new CGI;
my $remoteaddr = $query->remote_addr();
# The traffic is being forwarded through quest, so normally we see quest's local address as the remote address.
# Let's see if we have the real remote address in the environment.
if ( exists($ENV{HTTP_X_FORWARDED_FOR}) && $ENV{HTTP_X_FORWARDED_FOR} =~ m/^(\d+\.\d+\.\d+\.\d+)$/ )
{
    $remoteaddr = $1;
}
my %config = get_parameters($query, \%lname_by_code);
$query->charset('utf-8'); # makes the charset explicitly appear in the headers
print($query->header());
print(common::generate_html_start('deprels'));
#------------------------------------------------------------------------------
# If there were low-level errors in the parameters, print the error messages
# and exit.
if(scalar(@{$config{errors}}) > 0)
{
    print("<h1>Error in parameters:</h1>\n");
    foreach my $error (@{$config{errors}})
    {
        print("<p>".htmlescape($error)."</p>\n");
    }
}
#------------------------------------------------------------------------------
# No language code specified. Show the list of known languages.
elsif($config{lcode} eq '')
{
    print("  <h1>Specify dependency relations for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_deprel.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit deprels of that language.
else
{
    # Read the data file from JSON.
    my $data = valdata::read_deprels_json($path);
    my %data = %{$data};
    foreach my $lcode (keys(%data))
    {
        if(!exists($lname_by_code{$lcode}))
        {
            confess("Unknown language code '$lcode' in the JSON file");
        }
    }
    # Perform an action according to the CGI parameters.
    if($config{save})
    {
        process_form_data(\%data, $query);
    }
    # If we are not saving but have received a deprel, it means the deprel should be edited.
    elsif($config{deprel} ne '')
    {
        summarize_guidelines();
        print_deprel_details(\%data);
        # Do not offer editing for undocumented deprels!
        if(exists($data{$config{lcode}}{$config{deprel}}) && $data{$config{lcode}}{$config{deprel}}{doc} =~ m/^(global|local)$/)
        {
            print_deprel_form(\%data);
        }
        print_all_deprels(\%data, $languages);
    }
    else
    {
        summarize_guidelines();
        print_deprels_for_language(\%data);
        # Show all known deprels so the user can compare. This and related languages first.
        print_all_deprels(\%data, $languages);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of deprels permitted in the current language.
#------------------------------------------------------------------------------
sub print_deprels_for_language
{
    my $data = shift;
    if(exists($data->{$config{lcode}}))
    {
        my $ldata = $data->{$config{lcode}};
        my @deprels = sort(keys(%{$ldata}));
        my @deprels_on = grep {$ldata->{$_}{permitted}} (@deprels);
        my @deprels_off = grep {!$ldata->{$_}{permitted} && $ldata->{$_}{doc} =~ m/^(global|local)$/} (@deprels);
        my @udeprels_off = grep {$ldata->{$_}{type} eq 'universal'} (@deprels_off);
        my @ldeprels_off = grep {$ldata->{$_}{type} ne 'universal'} (@deprels_off); # type is 'global' or 'lspec', although type in docdeps.json is 'global' or 'local'
        my @undocumented = grep {$ldata->{$_}{doc} !~ m/^(global|local)$/} (@deprels);
        print("  <h2>Deprels</h2>\n");
        if(scalar(@deprels_on) > 0)
        {
            print("  <p><b>Currently permitted:</b> ".join(', ', map {"<a href=\"specify_deprel.pl?lcode=$config{lcode}&amp;deprel=$_\">$_</a>"} (@deprels_on))."</p>\n");
        }
        if(scalar(@udeprels_off) > 0)
        {
            print("  <p><b>Currently unused universal dependency relations:</b> ".join(', ', map {"<a href=\"specify_deprel.pl?lcode=$config{lcode}&amp;deprel=$_\">$_</a>"} (@udeprels_off))."</p>\n");
        }
        if(scalar(@ldeprels_off) > 0)
        {
            print("  <p><b>Other dependency relations that can be permitted:</b> ".join(', ', map {"<a href=\"specify_deprel.pl?lcode=$config{lcode}&amp;deprel=$_\">$_</a>"} (@ldeprels_off))."</p>\n");
        }
        if(scalar(@undocumented) > 0)
        {
            print("  <p><b>Undocumented dependency relations cannot be used:</b> ".join(', ', @undocumented)."</p>\n");
        }
        #print("  <p><b>DEBUGGING: All deprels known in relation to this language:</b> ".join(', ', map {"$_ ($ldata->{$_}{type}, $ldata->{$_}{doc}, $ldata->{$_}{permitted})"} (@deprels))."</p>\n");
        my @errors = ();
        foreach my $f (@deprels)
        {
            my $howdoc = $ldata->{$f}{doc} =~ m/^(global|gerror)$/ ? 'global' : $ldata->{$f}{doc} =~ m/^(local|lerror)$/ ? 'local' : 'none';
            my $href;
            my $file = $f;
            $file =~ s/:/-/g;
            if($howdoc eq 'global')
            {
                $href = "https://universaldependencies.org/u/dep/$file.html";
            }
            elsif($howdoc eq 'local')
            {
                $href = "https://universaldependencies.org/$config{lcode}/dep/$file.html";
            }
            if(defined($ldata->{$f}{errors}))
            {
                foreach my $e (@{$ldata->{$f}{errors}})
                {
                    push(@errors, "ERROR in <a href=\"$href\">documentation</a> of $f: $e");
                }
            }
        }
        if(scalar(@errors) > 0)
        {
            print("  <h2>Errors in documentation</h2>\n");
            print("  <ul>\n");
            foreach my $e (@errors)
            {
                print("    <li style='color:red'>$e</li>\n");
            }
            print("  </ul>\n");
        }
    }
    else
    {
        die("No information about dependency relations for language '$config{lcode}'");
    }
}



#------------------------------------------------------------------------------
# Prints information about a given deprel in a given language.
#------------------------------------------------------------------------------
sub print_deprel_details
{
    my $data = shift;
    if(exists($data->{$config{lcode}}))
    {
        print("  <h2>$config{deprel}</h2>\n");
        if(exists($data->{$config{lcode}}{$config{deprel}}))
        {
            my $fdata = $data->{$config{lcode}}{$config{deprel}};
            my $type = $fdata->{type};
            $type = 'language-specific' if($type eq 'lspec');
            my $howdoc = $fdata->{doc} =~ m/^(global|gerror)$/ ? 'global' : $fdata->{doc} =~ m/^(local|lerror)$/ ? 'local' : 'none';
            my $href;
            my $file = $config{deprel};
            $file =~ s/:/-/g;
            if($howdoc eq 'global')
            {
                $href = "https://universaldependencies.org/u/dep/$file.html";
            }
            elsif($howdoc eq 'local')
            {
                $href = "https://universaldependencies.org/$config{lcode}/dep/$file.html";
            }
            if($fdata->{permitted})
            {
                my $howdocly = $howdoc.'ly';
                print("  <p>This $type dependency relation is currently permitted in $lname_by_code{$config{lcode}} ".
                           "and is $howdocly documented <a href=\"$href\">here</a>.</p>\n");
            }
            else
            {
                print("  <p>This $type dependency relation is currently not permitted in $lname_by_code{$config{lcode}}.");
                if($howdoc eq 'none')
                {
                    print(" It is not documented.");
                }
                else
                {
                    my $howdocly = $howdoc.'ly';
                    print(" It is $howdocly documented <a href=\"$href\">here</a>.</p>\n");
                }
                print("</p>\n");
                if(scalar(@{$fdata->{errors}}) > 0)
                {
                    print("  <h3>Errors in $howdoc <a href=\"$href\">documentation</a></h3>\n");
                    print("  <ul>\n");
                    for my $e (@{$fdata->{errors}})
                    {
                        print("    <li style='color:red'>$e</li>\n");
                    }
                    print("  </ul>\n");
                }
            }
        }
        else
        {
            die("No information about dependency relation '$config{deprel}' in language '$config{lcode}'");
        }
    }
    else
    {
        die("No information about dependency relations for language '$config{lcode}'");
    }
}



#------------------------------------------------------------------------------
# Prints the form where a particular deprel can be edited.
#------------------------------------------------------------------------------
sub print_deprel_form
{
    my $data = shift;
    if($config{deprel} eq '')
    {
        die("Unknown deprel");
    }
    if(!exists($data->{$config{lcode}}{$config{deprel}}))
    {
        die("Dependency relation '$config{deprel}' not found in language '$config{lcode}'");
    }
    my $hdeprel = htmlescape($config{deprel});
    my $hlanguage = htmlescape($lname_by_code{$config{lcode}});
    print("  <h3>Permit or forbid $hdeprel</h3>\n");
    print <<EOF
  <form action="specify_deprel.pl" method="post" enctype="multipart/form-data">
  <input name=lcode type=hidden value="$config{lcode}" />
  <input name=deprel type=hidden value="$hdeprel" />
  <p>Please tell us your Github user name:
    <input name=ghu type=text value="$config{ghu}" />
    Are you a robot? (one word) <input name=smartquestion type=text size=10 /><br />
    <small>Your edits will be ultimately propagated to UD Github repositories
    and we need to be able to link them to a particular user if there are any
    issues to be discussed. This is not a problem when you edit directly on
    Github, but here the actual push action will be formally done by another
    user.</small></p>
EOF
    ;
    my $checked = $data->{$config{lcode}}{$config{deprel}}{permitted} ? ' checked' : '';
    print("  <p>Check <input type=\"checkbox\" id=\"permitted\" name=\"permitted\" value=\"1\"$checked /> here\n");
    print("    if $hdeprel should be permitted in $hlanguage.</p>\n");
    print("  <input name=save type=submit value=\"Save\" />\n");
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Processes data submitted from a form and prints confirmation or an error
# message.
# We are processing a Save request after a deprel was edited.
# We have briefly checked that the parameters match expected regular expressions.
# Nevertheless, only now we can also report an error if a parameter is empty.
#------------------------------------------------------------------------------
sub process_form_data
{
    my $data = shift;
    my $query = shift;
    my $error = 0;
    print("  <h2>This is a result of a Save button</h2>\n");
    print("  <ul>\n");
    if($config{ghu} ne '')
    {
        print("    <li>user = '$config{ghu}'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing Github user name</li>\n");
        $error = 1;
    }
    if($config{smartquestion} eq 'no')
    {
        print("    <li>robot = '$config{smartquestion}'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Unsatisfactory robotic response</li>\n");
        $error = 1;
    }
    if($config{deprel} ne '')
    {
        print("    <li>deprel = '$config{deprel}'</li>\n");
        # Check that the deprel is known and documented.
        if(exists($data->{$config{lcode}}{$config{deprel}}))
        {
            if($data->{$config{lcode}}{$config{deprel}}{doc} =~ m/^(global|local)$/)
            {
                if($config{permitted})
                {
                    if($data->{$config{lcode}}{$config{deprel}}{permitted})
                    {
                        print("    <li>No change: still permitted</li>\n");
                    }
                    else
                    {
                        print("    <li style='color:blue'>Now permitted</li>\n");
                    }
                }
                else
                {
                    if($data->{$config{lcode}}{$config{deprel}}{permitted})
                    {
                        print("    <li style='color:purple'>No longer permitted</li>\n");
                    }
                    else
                    {
                        print("    <li>No change: still not permitted</li>\n");
                    }
                }
            }
            else
            {
                print("    <li style='color:red'>ERROR: Undocumented dependency relation '$config{deprel}' cannot be used in language '$config{language}'</li>\n");
                $error = 1;
            }
        }
        else
        {
            print("    <li style='color:red'>ERROR: Unknown dependency relation '$config{deprel}' in language '$config{language}'</li>\n");
            $error = 1;
        }
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing deprel</li>\n");
        $error = 1;
    }
    print("  </ul>\n");
    if($error)
    {
        print("  <p style='color:red'><strong>WARNING:</strong> Nothing was saved because there were errors.</p>\n");
    }
    else
    {
        my $ddata = $data->{$config{lcode}}{$config{deprel}};
        # Do I want to use my local time or universal time in the timestamps?
        #my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = localtime(time());
        my $timestamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 1900+$year, 1+$mon, $mday, $hour, $min, $sec);
        $ddata->{lastchanged} = $timestamp;
        $ddata->{lastchanger} = $config{ghu};
        $ddata->{permitted} = $config{permitted};
        valdata::write_deprels_json($data, "$path/deprels.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_deprel.pl" method="post" enctype="multipart/form-data">
    <input name=lcode type=hidden value="$config{lcode}" />
    <input name=ghu type=hidden value="$config{ghu}" />
    <input name=gotolang type=submit value="Return to list" />
  </form>
EOF
        ;
    }
}



#------------------------------------------------------------------------------
# Prints the introductory information.
#------------------------------------------------------------------------------
sub summarize_guidelines
{
    print <<EOF
  <h1><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$lname_by_code{$config{lcode}}}{flag}.png\" />
    Specify dependency relations for $lname_by_code{$config{lcode}}</h1>
  <p>A dependency relation subtype will be permitted in the language only if it is registered
    here. All relations must be documented. If you need a language-specific relation subtype
    that is not yet available here, write its language-specific documentation page (see
    <a href="https://universaldependencies.org/contributing_language_specific.html#language-specific-subtypes-of-dependency-relations">here</a>
    for instructions).</p>
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints deprels of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_deprels
{
    my $data = shift;
    my $languages = shift; # ref to hash read from YAML, indexed by names
    # Print the data on the web page.
    print("  <h2>Permitted dependency relations for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    # Get the list of all known deprels. Take only the main types; we will display their subtypes in the same cell.
    my %udeprels;
    my %deprels;
    foreach my $lcode (@lcodes)
    {
        my @deprels = keys(%{$data->{$lcode}});
        foreach my $d (@deprels)
        {
            if($data->{$lcode}{$d}{permitted})
            {
                $deprels{$d}++;
                my $ud = $d;
                $ud =~ s/:.*//;
                $udeprels{$ud}++;
            }
        }
    }
    my @deprels = sort(keys(%deprels));
    my @udeprels = sort(keys(%udeprels));
    print("  <table>\n");
    my $i = 0;
    foreach my $lcode (@lcodes)
    {
        # Collect language-specific subtypes of relations.
        my %subtypes;
        foreach my $d (keys(%{$data->{$lcode}}))
        {
            if($data->{$lcode}{$d}{permitted})
            {
                if($d =~ m/^([a-z]+):([a-z]+)$/)
                {
                    my $udep = $1;
                    my $lspec = $2;
                    $subtypes{$udep}{$lspec}++;
                }
            }
        }
        # Repeat the headers every 20 rows.
        if($i % 20 == 0)
        {
            print("    <tr><th colspan=2>Language</th><th>Total</th>");
            my $j = 0;
            foreach my $d (@udeprels)
            {
                # Repeat the language every 12 columns.
                if($j != 0 && $j % 12 == 0)
                {
                    print('<th></th>');
                }
                $j++;
                print("<th>$d</th>");
            }
            print("</tr>\n");
        }
        $i++;
        # Get the number of deprels permitted in this language.
        my $n = scalar(grep {exists($data->{$lcode}{$_}) && $data->{$lcode}{$_}{permitted}} (@deprels));
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
        my $j = 0;
        foreach my $d (@udeprels)
        {
            # Repeat the language every 12 columns.
            if($j != 0 && $j % 12 == 0)
            {
                print("<td><b>$lcode</b></td>");
            }
            $j++;
            print('<td>');
            my $dp = '';
            if(exists($data->{$lcode}{$d}) && $data->{$lcode}{$d}{permitted})
            {
                $dp = $d;
            }
            my $s = '';
            if(exists($subtypes{$d}))
            {
                $dp = "($d)" if($dp eq '');
                my @subtypes = sort(keys(%{$subtypes{$d}}));
                $s = '<br />'.join('<br />', map {"↳:$_"} (@subtypes));
            }
            print($dp.$s);
            print('</td>');
        }
        print("</tr>\n");
    }
    print("  </table>\n");
}



#------------------------------------------------------------------------------
# Reads the CGI parameters, checks their values and untaints them so that they
# can be safely used in the code. Untainting happens when the value is run
# through a regular expression. The untainted values are stored in a hash, and
# a reference to the hash is returned. The hash also contains an array
# reference under the key 'errors'. If a parameter contains unexpected
# characters, an error message will be added to the array and the value of the
# parameter will not be accepted. The caller may then decide whether or not to
# report the error and whether or not to treat it as fatal.
#------------------------------------------------------------------------------
sub get_parameters
{
    my $query = shift; # The CGI object that can supply the parameters.
    my $lname_by_code = shift; # hash ref
    my %config; # our hash where we store the parameters
    my @errors; # we store error messages about parameters here
    $config{errors} = \@errors;
    # Certain characters are not letters but they are used regularly between
    # letters in certain writing systems, hence they must be permitted.
    # ZERO WIDTH JOINER (\x{200D}) is category C (other); used in Devanagari, for instance.
    my $zwj = "\x{200D}";
    #--------------------------------------------------------------------------
    # Language code. If not provided, we show the introductory list of
    # languages.
    $config{lcode} = decode('utf8', $query->param('lcode'));
    if(!defined($config{lcode}) || $config{lcode} =~ m/^\s*$/)
    {
        $config{lcode} = '';
    }
    elsif($config{lcode} =~ m/^([a-z]{2,3})$/)
    {
        $config{lcode} = $1;
        if(!exists($lname_by_code->{$config{lcode}}))
        {
            push(@errors, "Unknown language code '$config{lcode}'");
        }
    }
    else
    {
        push(@errors, "Language code '$config{lcode}' does not consist of two or three lowercase English letters");
    }
    #--------------------------------------------------------------------------
    # Github user name. Some names may look like e-mail addresses.
    $config{ghu} = decode('utf8', $query->param('ghu'));
    if(!defined($config{ghu}) || $config{ghu} =~ m/^\s*$/)
    {
        $config{ghu} = '';
    }
    elsif($config{ghu} =~ m/^([-A-Za-z_0-9\@\.]+)$/)
    {
        $config{ghu} = $1;
    }
    else
    {
        push(@errors, "Unrecognized name '$config{ghu}'");
    }
    #--------------------------------------------------------------------------
    # Smart question is a primitive measure against robots that find the page
    # accidentally. Expected answer is "no".
    $config{smartquestion} = decode('utf8', $query->param('smartquestion'));
    if(!defined($config{smartquestion}) || $config{smartquestion} =~ m/^\s*$/)
    {
        $config{smartquestion} = '';
    }
    elsif($config{smartquestion} =~ m/^\s*no\s*$/i)
    {
        $config{smartquestion} = 'no';
    }
    else
    {
        push(@errors, "Unsatisfactory robotic response :-)");
    }
    #--------------------------------------------------------------------------
    # Deprel is the name of the deprel whose details we want to see and edit.
    $config{deprel} = decode('utf8', $query->param('deprel'));
    if(!defined($config{deprel}) || $config{deprel} =~ m/^\s*$/)
    {
        $config{deprel} = '';
    }
    # Forms of deprels are prescribed in the UD guidelines.
    elsif($config{deprel} =~ m/^([a-z]+(:[a-z]+)?)$/)
    {
        $config{deprel} = $1;
    }
    else
    {
        push(@errors, "Deprel '$config{deprel}' does not have the form prescribed by the guidelines");
    }
    #--------------------------------------------------------------------------
    # Permitted is a boolean (=1) parameter that says whether a given deprel is
    # permitted in the language.
    $config{permitted} = decode('utf8', $query->param('permitted'));
    if(!defined($config{permitted}) || $config{permitted} =~ m/^\s*$/ || $config{permitted} == 0)
    {
        $config{permitted} = '';
    }
    elsif($config{permitted} =~ m/^0*1$/)
    {
        $config{permitted} = 1;
    }
    else
    {
        push(@errors, "Unexpected value '$config{permitted}' of the parameter 'permitted'");
    }
    #--------------------------------------------------------------------------
    # The parameter 'save' comes from the Save button which submitted the form.
    $config{save} = decode('utf8', $query->param('save'));
    if(!defined($config{save}))
    {
        $config{save} = 0;
        $config{savenew} = 0;
    }
    elsif($config{save} =~ m/^Save$/)
    {
        $config{save} = 1;
        $config{savenew} = 0;
    }
    else
    {
        push(@errors, "Unrecognized save button '$config{save}'");
    }
    return %config;
}



#------------------------------------------------------------------------------
# Escapes HTML control characters in a string.
#------------------------------------------------------------------------------
sub htmlescape
{
    my $x = shift;
    $x =~ s/&/&amp;/g;
    $x =~ s/</&lt;/g;
    $x =~ s/>/&gt;/g;
    return $x;
}
