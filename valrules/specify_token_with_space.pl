#!/usr/bin/perl -wT

use strict;
use utf8;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use File::Basename;
use JSON::Parse 'json_file_to_perl';
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
use valdata;
use langgraph;

# Read the list of known languages.
my $languages = LoadFile($path.'/../codes_and_flags.yaml');
if ( !defined($languages) )
{
    die "Cannot read the list of languages";
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
print <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify auxiliaries in UD</title>
  <link rel="icon" href="https://universaldependencies.org/logos/logo-ud.png" type="image/png">
  <style type="text/css">
    img {border: none;}
    img.flag {
      vertical-align: middle;
      border: solid grey 1px;
      height: 1em;
    }
  </style>
</head>
<body>
  <p style="position: absolute; right: 10px; font-size:0.8em">
    <a href="specify_auxiliary.pl">a</a>
    <a href="specify_feature.pl">f</a>
    <a href="specify_deprel.pl">d</a>
    <a href="specify_edeprel.pl">e</a>
  </p>
EOF
;
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
    print("  <h1>Specify tokens with spaces for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_token_with_space.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit tokens with spaces of that language.
else
{
    # Read the data file from JSON.
    my %data = read_data_json();
    # Perform an action according to the CGI parameters.
    if($config{save})
    {
        process_form_data(\%data);
    }
    # If we are not saving but have received an expression, it means the expression should be edited.
    elsif($config{expression} ne '')
    {
        summarize_guidelines();
        print_expression_form(\%data);
        print_all_expressions(\%data, $languages);
    }
    elsif($config{add})
    {
        summarize_guidelines();
        print_expression_form(\%data);
        print_all_expressions(\%data, $languages);
    }
    else
    {
        summarize_guidelines();
        print_edit_add_menu(\%data);
        # Show all known auxiliaries so the user can compare. This and related languages first.
        print_all_expressions(\%data, $languages);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of expressions for editing and the button to add a new
# expression.
#------------------------------------------------------------------------------
sub print_edit_add_menu
{
    my $data = shift;
    print("  <h2>Edit or add regular expressions</h2>\n");
    my @ndcop = ();
    if(exists($data->{$config{lcode}}))
    {
        my @expressions = sort(keys(%{$data->{$config{lcode}}}));
        my $hrefs = get_expression_links_to_edit(@expressions);
        print("  <p>$hrefs</p>\n");
    }
    print("  <form action=\"specify_token_with_space.pl\" method=\"post\" enctype=\"multipart/form-data\">\n");
    print("    <input name=lcode type=hidden value=\"$config{lcode}\" />\n");
    print("    <input name=ghu type=hidden value=\"$config{ghu}\" />\n");
    print("    <input name=add type=submit value=\"Add\" />\n");
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Returns a list of expressions as HTML links to the edit form.
#------------------------------------------------------------------------------
sub get_expression_links_to_edit
{
    my @expressions = @_;
    my @hrefs;
    foreach my $expression (@expressions)
    {
        # The expression may contain various special characters which must be escaped in a URL.
        my $urlexpression = uri_escape_utf8($expression);
        my $href = "<a href=\"specify_token_with_space.pl?ghu=$config{ghu}&amp;lcode=$config{lcode}&amp;expression=$urlexpression\">$expression</a>";
        push(@hrefs, $href);
    }
    return join(' ', @hrefs);
}



#------------------------------------------------------------------------------
# Prints the form where a particular expression can be edited.
#------------------------------------------------------------------------------
sub print_expression_form
{
    my $data = shift;
    # This function can be called for an empty expression, in which case we want
    # to add a new one. However, if the expression is non-empty, it must be
    # known.
    my $record;
    if($config{expression} eq '')
    {
        $record =
        {
            'status'    => 'new'
        };
    }
    elsif(exists($data->{$config{lcode}}{$config{expression}}))
    {
        $record = $data->{$config{lcode}}{$config{expression}};
    }
    else
    {
        die("Expression '$config{expression}' not found in language '$config{lcode}'");
    }
    my $show_exampleen = $config{lcode} ne 'en';
    print <<EOF
  <form action="specify_token_with_space.pl" method="post" enctype="multipart/form-data">
  <input name=lcode type=hidden value="$config{lcode}" />
  <p>Please tell us your Github user name:
    <input name=ghu type=text value="$config{ghu}" />
    Are you a robot? (one word) <input name=smartquestion type=text size=10 /><br />
    <small>Your edits will be ultimately propagated to UD Github repositories
    and we need to be able to link them to a particular user if there are any
    issues to be discussed. This is not a problem when you edit directly on
    Github, but here the actual push action will be formally done by another
    user.</small></p>
  <table id="inputtable">
EOF
    ;
    #--------------------------------------------------------------------------
    # Column headings
    print("    <tr id=\"inputheader\">\n");
    print("      <td>Expression</td>\n");
    print("      <td>Example</td>\n");
    if($show_exampleen)
    {
        print("      <td>English translation of the example</td>\n");
    }
    print("      <td>Comment</td>\n");
    print("    </tr>\n");
    #--------------------------------------------------------------------------
    # Expression
    print("    <tr id=\"inputrow1\">\n");
    print("      <td>");
    if($config{expression} ne '')
    {
        my $hexpression = htmlescape($config{expression});
        print("<strong>$hexpression</strong><input name=expression type=hidden size=10 value=\"$hexpression\" />");
    }
    else
    {
        print("<input name=expression type=text size=10 />");
    }
    print("</td>\n");
    my $hexample = '';
    print("      <td><input name=example1 type=text size=30 value=\"$hexample\" /></td>\n");
    if($show_exampleen)
    {
        my $hexampleen = '';
        print("      <td><input name=exampleen1 type=text size=30 value=\"$hexampleen\" /></td>\n");
    }
    my $hcomment = '';
    print("      <td><input name=comment1 type=text value=\"$hcomment\" /></td>\n");
    print("    </tr>\n");
    #--------------------------------------------------------------------------
    # Buttons
    print("  </table>\n");
    # If we are adding a new expression, we will have to check that it is really new.
    # Signal that with a slightly different button text, "Save new" instead of "Save".
    if($config{add})
    {
        print("      <input name=save type=submit value=\"Save new\" />\n");
    }
    else
    {
        print("      <input name=save type=submit value=\"Save\" />\n");
    }
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Processes data submitted from a form and prints confirmation or an error
# message.
# We are processing a Save request after an expression was edited.
# We have briefly checked that the parameters match expected regular expressions.
# Nevertheless, only now we can also report an error if a parameter is empty.
#------------------------------------------------------------------------------
sub process_form_data
{
    my $data = shift;
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
    if($config{expression} ne '')
    {
        print("    <li>expression = '$config{expression}'</li>\n");
        if($config{savenew} && exists($data->{$config{lcode}}{$config{expression}}))
        {
            print("    <li style='color:red'>ERROR: The expression '$config{expression}' is already registered. Instead of re-adding it, you should edit it</li>\n");
            $error = 1;
        }
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing expression</li>\n");
        $error = 1;
    }
    print("  </ul>\n");
    if($error)
    {
        print("  <p style='color:red'><strong>WARNING:</strong> Nothing was saved because there were errors.</p>\n");
    }
    else
    {
        # Create a new record. Even if we are editing an existing expression,
        # all previous values will be thrown away and replaced with the new
        # ones.
        my %record;
        # Do I want to use my local time or universal time in the timestamps?
        #my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = localtime(time());
        my $timestamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 1900+$year, 1+$mon, $mday, $hour, $min, $sec);
        $record{lastchanged} = $timestamp;
        $record{lastchanger} = $config{ghu};
        $record{expression} = $config{expression};
        $record{example} = $config{example};
        $record{exampleen} = $config{exampleen};
        $data->{$config{lcode}}{$config{expression}} = \%record;
        write_data_json($data, "$path/tospace.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_token_with_space.pl" method="post" enctype="multipart/form-data">
    <input name=lcode type=hidden value="$config{lcode}" />
    <input name=ghu type=hidden value="$config{ghu}" />
    <input name=gotolang type=submit value="Return to list" />
  </form>
EOF
        ;
    }
}



#------------------------------------------------------------------------------
# Prints the guidelines.
#------------------------------------------------------------------------------
sub summarize_guidelines
{
    print <<EOF
  <h1><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$lname_by_code{$config{lcode}}}{flag}.png\" />
    Specify tokens with spaces for $lname_by_code{$config{lcode}}</h1>
  <p>The guidelines exceptionally allow tokens (words) with internal spaces.
    Each such case must be documented for each language separately. Acceptable
    cases include long numbers where spaces are added for readability (e.g.,
    English <i>1,000,000</i> is spelled <i>1&nbsp;000&nbsp;000</i> in some
    languages) or fixed expressions that can be correctly spelled both with and
    without space. The only language where words with spaces are allowed
    broadly is Vietnamese, where spaces delimit monosyllabic morphs rather than
    words.</p>
  <p>Each type of a token with space can be registered here as a regular
    expression. The space must occur internally (no leading or trailing spaces)
    and multiple consecutive spaces are not allowed. Once registered, strings
    matching the regular expression will be permitted in the FORM and LEMMA
    columns of the <a href="https://universaldependencies.org/format.html">CoNLL-U
    format</a>.</p>
  <p>Within the regular expression, the following characters have special
    meaning:</p>
  <ul>
    <li>Square brackets denote a set of characters, one of which is expected at
      the given position. For example, <tt>[kcq]</tt> matches either “k” or “c”
      or “q”. A hyphen inside square brackets is used for ranges of characters,
      so <tt>[0-9]</tt> matches any of the ten digits used in English.</li>
    <li>Question mark after a character says that the character is optional. For
      example, <tt>e?</tt> matches either “e” or the empty string “”. Star after
      a character says that the character can occur any number of times:
      <tt>e*</tt> matches “”, “e”, “ee”, …, “eeeeeee” etc. Plus after a character
      means that the character can occur multiple times but it must occur at
      least once: <tt>e+</tt> matches “e”, “ee”, …, “eeeeeee” etc.</li>
    <li>The operators <tt>?</tt>, <tt>*</tt>, and <tt>+</tt> can be applied to
      a string enclosed in round brackets. For example, <tt>(yes)+</tt> matches
      “yes”, “yesyes” etc.</li>
    <li>Vertical bar inside round brackets means disjunction of strings. Thus
      <tt>(yes|no)+</tt> matches “yes”, “no”, “yesyes”, “yesno”, “nono”,
      “noyes”, “yesyesyes” etc.</li>
  </ul>
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints auxiliaries of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_expressions
{
    my $data = shift;
    my $languages = shift; # ref to hash read from YAML, indexed by names
    # Print the data on the web page.
    print("  <h2>Known auxiliaries for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    print("  <table>\n");
    print("    <tr><th colspan=2>Language</th><th>Total</th></tr>\n");
    foreach my $lcode (@lcodes)
    {
        my $ldata = $data->{$lcode};
        my @expressions = sort(keys(%{$ldata}));
        my $n = scalar(@expressions);
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
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
    # ZERO WIDTH NON-JOINER (\x{200C}) is category C (other); used in Persian, for instance.
    my $zwnj = "\x{200C}";
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
    # Expression is the regular expression describing one type of words with
    # spaces. We should be careful and allow only a subset of Perl RE syntax,
    # excluding anything that can lead to execution of arbitrary code.
    $config{expression} = decode('utf8', $query->param('expression'));
    if(!defined($config{expression}) || $config{expression} =~ m/^\s*$/)
    {
        $config{expression} = '';
    }
    # Expression contains at least one space.
    # Besides that, it can contain letters (L) and marks (M).
    # An example of a mark: U+94D DEVANAGARI SIGN VIRAMA.
    elsif($config{expression} =~ m/^\s*([\pL\pM]+([-' ][\pL\pM]+)?)\s*$/) #'
    {
        $config{expression} = $1;
        # First primitive adjustments of the expression.
        $config{expression} =~ s/\\s/ /g;
        $config{expression} =~ s/^ +//;
        $config{expression} =~ s/ +$//;
        $config{expression} =~ s/ +/ /g;
        if($config{expression} !~ m/ /)
        {
            push(@errors, "Expression '$config{expression}' does not contain the space character");
        }
    }
    else
    {
        push(@errors, "Expression '$config{expression}' contains non-letter characters");
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
    elsif($config{save} =~ m/^Save new$/)
    {
        $config{save} = 1;
        $config{savenew} = 1;
    }
    else
    {
        push(@errors, "Unrecognized save button '$config{save}'");
    }
    #--------------------------------------------------------------------------
    # The parameter 'add' comes from the button that launches the form to add
    # a new expression.
    $config{add} = decode('utf8', $query->param('add'));
    if(!defined($config{add}))
    {
        $config{add} = 0;
    }
    elsif($config{add} =~ m/^Add$/)
    {
        $config{add} = 1;
    }
    else
    {
        push(@errors, "Unrecognized add button '$config{add}'");
    }
    return %config;
}



#------------------------------------------------------------------------------
# Reads the regular expressions from the JSON file.
#------------------------------------------------------------------------------
sub read_data_json
{
    my %data;
    my $datafile = "$path/tospace.json";
    my $json = json_file_to_perl($datafile);
    # The $json structure should contain two items, 'WARNING' and 'expressions';
    # the latter should be a reference to an hash of arrays of hashes.
    if(exists($json->{expressions}) && ref($json->{expressions}) eq 'HASH')
    {
        my @lcodes = keys(%{$json->{expressions}});
        foreach my $lcode (@lcodes)
        {
            if(!exists($lname_by_code{$lcode}))
            {
                die("Unknown language code '$lcode' in the JSON file");
            }
            my @expressions = keys(%{$json->{expressions}{$lcode}});
            foreach my $expression (@expressions)
            {
                # We do not have to copy the data item by item to a new record.
                # We can simply copy the reference to the record.
                $data{$lcode}{$expression} = $json->{expressions}{$lcode}{$expression};
            }
        }
    }
    else
    {
        die("No expressions found in the JSON file");
    }
    return %data;
}



#------------------------------------------------------------------------------
# Dumps the data as a JSON file.
#------------------------------------------------------------------------------
sub write_data_json
{
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl instead.",'."\n\n";
    $json .= '"expressions": {'."\n";
    my @jsonlanguages = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my $jsonlanguage = '"'.$lcode.'"'.": {\n";
        my @jsonexpressions = ();
        my @expressions = sort(keys(%{$data->{$lcode}}));
        foreach my $expression (@expressions)
        {
            my $jsonexpression = '"'.valdata::escape_json_string($expression).'": ';
            my @record =
            (
                ['status'      => $data->{$lcode}{$expression}{status}],
                ['lastchanged' => $data->{$lcode}{$expression}{lastchanged}],
                ['lastchanger' => $data->{$lcode}{$expression}{lastchanger}]
            );
            $jsonexpression .= valdata::encode_json(@record);
            push(@jsonexpressions, $jsonexpression);
        }
        $jsonlanguage .= join(",\n", @jsonexpressions)."\n";
        $jsonlanguage .= '}';
        push(@jsonlanguages, $jsonlanguage);
    }
    $json .= join(",\n", @jsonlanguages)."\n";
    $json .= "}}\n";
    open(JSON, ">$filename") or die("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
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
