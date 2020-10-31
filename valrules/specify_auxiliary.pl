#!/usr/bin/perl -wT

use strict;
use utf8;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use JSON::Parse 'json_file_to_perl';
use YAML qw(LoadFile);
#binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use open ':utf8';
use Encode;

# Path to the data on the web server.
my $path = '/home/zeman/unidep/docs-automation/valrules';
# Read the list of known languages.
my $languages = LoadFile('/home/zeman/unidep/docs-automation/codes_and_flags.yaml');
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
my @functions =
(
    ['Copula', 'cop'],
    ['Periphrastic aspect: perfect', 'Aspect=Perf'],
    ['Periphrastic aspect: progressive', 'Aspect=Prog'],
    ['Periphrastic tense: past', 'Tense=Past'],
    ['Periphrastic tense: future', 'Tense=Fut'],
    ['Periphrastic voice: passive', 'Voice=Pass'],
    ['Periphrastic voice: causative', 'Voice=Cau'],
    ['Periphrastic mood: conditional', 'Mood=Cnd'],
    ['Periphrastic mood: imperative', 'Mood=Imp'],
    ['Needed in negative clauses (like English “do”, not like “not”)', 'negative'],
    ['Needed in interrogative clauses (like English “do”)', 'interrogative'],
    ['Modal auxiliary: necessitative (“must, should”)', 'Mood=Nec'],
    ['Modal auxiliary: potential (“can, might”)', 'Mood=Pot'],
    ['Modal auxiliary: desiderative (“want”)', 'Mood=Des']
);
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
my %config = get_parameters($query, \%lname_by_code, \@functions);
$query->charset('utf-8'); # makes the charset explicitly appear in the headers
print($query->header());
print <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify auxiliaries in UD</title>
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
EOF
;
#------------------------------------------------------------------------------
# No language code specified. Show the list of known languages.
if($config{lcode} eq '')
{
    print("  <h1>Specify auxiliaries for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_auxiliary.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit auxiliaries of that language.
else
{
    # Read the data file.
    my %data = read_auxiliaries_from_python();
    # It is possible that there are no auxiliaries for my language so far.
    my @myauxlist = ();
    if(exists($data{$config{lcode}}))
    {
        @myauxlist = map {$_->{lemma}} (@{$data{$config{lcode}}});
    }
    print <<EOF
  <h1><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$lname_by_code{$config{lcode}}}{flag}.png\" />
    Specify auxiliaries for $lname_by_code{$config{lcode}}</h1>
  <p><strong>Remember:</strong> Not everything that a traditional grammar labels
    as auxiliary is necessarily an <a href="https://universaldependencies.org/u/pos/AUX_.html">auxiliary in UD</a>.
    Just because a verb combines with another verb does not necessarily mean
    that one of the verbs is auxiliary; the usual alternative in UD is treating
    one of the verbs as an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    of the other, or in some languages as a serial verb construction
    (<tt><a href="https://universaldependencies.org/u/dep/compound.html">compound:svc</a></tt>).
    Language-specific tests whether a verb is auxiliary are
    grammatical rather than semantic: just because something has a modal or
    near-modal meaning does not mean that it is an auxiliary, and in some
    languages modal verbs do not count as auxiliaries at all. Some verbs
    function as auxiliaries in some constructions and as full verbs in others
    (e.g., <i>to have</i> in English). There are also auxiliaries whose nature
    is completely different from verbs in the given language.</p>
  <p><strong>Remember:</strong> A language typically has at most one lemma for
    <a href="https://universaldependencies.org/u/dep/cop.html">copula</a>.
    Exceptions include deficient paradigms (different present and past copula,
    positive and negative, imperfect and iterative), and also the Romance verbs
    <i>ser</i> and <i>estar</i> (both equivalents of “to be”). In contrast,
    equivalents of “to become, to stay, to look like, to be called” etc. are not copulas
    in UD, even if a traditional grammar classifies them as such. In UD they
    should head an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    relation instead. A copula is normally tagged <a href="https://universaldependencies.org/u/pos/AUX_.html">AUX</a>.
    Exception: in some languages a personal or demonstrative pronoun /
    determiner can be used as a copula and then we keep it tagged
    <a href="https://universaldependencies.org/u/pos/PRON.html">PRON</a> or
    <a href="https://universaldependencies.org/u/pos/DET.html">DET</a>.</p>
EOF
    ;
    #------------------------------------------------------------------------------
    # We are processing a Save request after a lemma was edited.
    # We have briefly checked that the parameters match expected regular expressions.
    # Nevertheless, only now we can also report an error if a parameter is empty.
    if($config{save})
    {
        print("  <h2>This is a result of a Save button</h2>\n");
        print("  <ul>\n");
        if($config{ghu} ne '')
        {
            print("    <li>user = '$config{ghu}'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing Github user name</li>\n");
        }
        if($config{smartquestion} eq 'no')
        {
            print("    <li>robot = '$config{smartquestion}'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Unsatisfactory robotic response</li>\n");
        }
        if($config{lemma} ne '')
        {
            print("    <li>lemma = '$config{lemma}'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing lemma</li>\n");
        }
        if($config{function} ne '')
        {
            print("    <li>function = '".htmlescape($config{function})."'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing function</li>\n");
        }
        if($config{example} ne '')
        {
            print("    <li>example = '".htmlescape($config{example})."'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing example</li>\n");
        }
        if($config{exampleen} ne '')
        {
            print("    <li>exampleen = '".htmlescape($config{exampleen})."'</li>\n");
        }
        elsif($config{lcode} ne 'en')
        {
            print("    <li style='color:red'>ERROR: Missing English translation of the example</li>\n");
        }
        if($config{comment} ne '')
        {
            print("    <li>comment = '".htmlescape($config{comment})."'</li>\n");
        }
        print("  </ul>\n");
        print("  <p style='color:red'><strong>WARNING:</strong> Real saving has not been implemented yet.</p>\n");
        write_data_json(\%data, "$path/data.json");
    }
    else
    {
        if($config{lemma} eq '')
        {
            my $n = scalar(@myauxlist);
            if($n > 0)
            {
                print("  <h2 style='color:red'>You have $n undocumented auxiliaries!</h2>\n");
                print("  <p>Please edit each undocumented auxiliary and supply the missing information.</p>\n");
                print("  <p>".join(' ', map {my $l = $_; $l =~ s/\PL//g; $l = 'XXX' if($l eq ''); "<a href=\"specify_auxiliary.pl?lcode=$config{lcode}&amp;lemma=$l\">$l</a>"} (@myauxlist))."</p>\n");
            }
        }
        else
        {
            print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
  <input name=lcode type=hidden value="$config{lcode}" />
  <p>Please tell us your Github user name:
    <input name=ghu type=text />
    Are you a robot? (one word) <input name=smartquestion type=text size=10 /><br />
    <small>Your edits will be ultimately propagated to UD Github repositories
    and we need to be able to link them to a particular user if there are any
    issues to be discussed. This is not a problem when you edit directly on
    Github, but here the actual push action will be formally done by another
    user.</small></p>
  <table>
    <tr>
      <td>Lemma</td>
      <td>Function</td>
      <td>Rule</td>
      <td>Example</td>
EOF
            ;
            unless($config{lcode} eq 'en')
            {
                print("      <td>English translation of the example</td>\n");
            }
            print <<EOF
      <td>Comment</td>
    </tr>
    <tr>
      <td><input name=lemma type=text size=10 value="$config{lemma}" /></td>
      <td>
        <select name=function>
          <option>-----</option>
EOF
            ;
            foreach my $f (@functions)
            {
                print("          <option>".htmlescape($f->[0])."</option>\n");
            }
            print <<EOF
        </select>
      </td>
      <td><input name=rule type=text size=30 /></td>
      <td><input name=example type=text size=30 /></td>
EOF
            ;
            unless($config{lcode} eq 'en')
            {
                print("      <td><input name=exampleen type=text size=30 /></td>\n");
            }
            print <<EOF
      <td><input name=comment type=text /></td>
    </tr>
    <tr>
      <td><input name=save type=submit value="Save" /></td>
      <td></td>
      <td><small>e.g. “combination of the auxiliary and a past participle of the main verb”</small></td>
      <td><small>mark the auxiliary by enclosing it in square brackets, e.g., “he [has] done it”</small></td>
      <!-- empty cells under english example and comment omitted (the one under english example would have to appear only if lcode is not en -->
    </tr>
  </table>
  </form>
EOF
            ;
        }
    }
    # Print the data on the web page.
    print("  <h2>Known auxiliaries for this and other languages</h2>\n");
    print("  <table>\n");
    print("    <tr><th colspan=2>Language</th><th>Total</th><th>Lemmas</th></tr>\n");
    # First display the actual language.
    # Then display languages from the same family and genus.
    # Then languages from the same family but different genera.
    # Then all remaining languages.
    my $myfamilygenus = $languages->{$lname_by_code{$config{lcode}}}{familygenus};
    my $myfamily = $languages->{$lname_by_code{$config{lcode}}}{family};
    my $mygenus = $languages->{$lname_by_code{$config{lcode}}}{genus};
    my @lcodes = sort(keys(%data));
    my @lcodes_my_genus = grep {$_ ne $config{lcode} && $languages->{$lname_by_lcode{$_}}{familygenus} eq $myfamilygenus} (@lcodes);
    my @lcodes_my_family = grep {$languages->{$lname_by_code{$_}}{familygenus} ne $myfamilygenus && $languages->{$lname_by_code{$_}}{family} eq $myfamily} (@lcodes);
    my @lcodes_other = grep {$languages->{$lname_by_code{$_}}{family} ne $myfamily} (@lcodes);
    foreach my $lcode ($config{lcode}, @lcodes_my_genus, @lcodes_my_family, @lcodes_other)
    {
        my @lemmas = map {$_->{lemma}} (@{$data{$lcode}});
        my $n = scalar(@lemmas);
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td><td>".join(' ', @lemmas)."</td></tr>\n");
    }
    print("  </table>\n");
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Reads the CGI parameters, checks their values and untaints them so that they
# can be safely used in the code. Untainting happens when the value is run
# through a regular expression.
#------------------------------------------------------------------------------
sub get_parameters
{
    my $query = shift; # The CGI object that can supply the parameters.
    my $lname_by_code = shift; # hash ref
    my $functions = shift; # ref to array of pairs (arrays)
    my %config; # our hash where we store the parameters
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
            die "Unknown language code '$config{lcode}'";
        }
    }
    else
    {
        die "Language code '$config{lcode}' does not consist of two or three lowercase English letters";
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
        die "Unrecognized name '$config{ghu}'";
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
        die "Unsatisfactory robotic response :-)";
    }
    #--------------------------------------------------------------------------
    # Lemma identifies the auxiliary that we are editing or going to edit.
    $config{lemma} = decode('utf8', $query->param('lemma'));
    if(!defined($config{lemma}) || $config{lemma} =~ m/^\s*$/)
    {
        $config{lemma} = '';
    }
    elsif($config{lemma} =~ m/^\s*(\pL+)\s*$/)
    {
        $config{lemma} = $1;
    }
    else
    {
        die "Lemma '$config{lemma}' contains non-letter characters";
    }
    #--------------------------------------------------------------------------
    # Function is a descriptive text (e.g. "Periphrastic aspect: perfect")
    # taken from a pre-defined list of options.
    $config{function} = decode('utf8', $query->param('function'));
    if(!defined($config{function}) || $config{function} =~ m/^\s*$/)
    {
        $config{function} = '';
    }
    else
    {
        if($config{function} =~ m/^(.+)$/)
        {
            $config{function} = $1;
        }
        # Verify that the function is one of the functions we defined.
        if(!scalar(grep {$_ eq $config{function}} (map {$_->[0]} (@{$functions}))))
        {
            die "Unrecognized function '$config{function}'";
        }
    }
    #--------------------------------------------------------------------------
    # Rule is a descriptive text (e.g. "combination of the auxiliary with
    # a participle of the main verb"). It is not restricted to a pre-defined
    # set of options but it should not need more than English letters, spaces,
    # and some basic punctuation.
    $config{rule} = decode('utf8', $query->param('rule'));
    if(!defined($config{rule}) || $config{rule} =~ m/^\s*$/)
    {
        $config{rule} = '';
    }
    elsif($config{rule} =~ m/^([-A-Za-z \.:\(,;\)]+)$/)
    {
        $config{rule} = $1;
    }
    else
    {
        die "Rule '$config{rule}' contains characters other than English letters, space, period, comma, semicolon, colon, hyphen, and round brackets";
    }
    #--------------------------------------------------------------------------
    # Example in the original language may contain letters (including Unicode
    # letters), spaces, punctuation (including Unicode punctuation). Square
    # brackets have a special meaning, they mark the word we focus on. We
    # probably do not need < > & "" and we could ban them for safety (but
    # it is not necessary if we make sure to always escape them when inserting
    # them in HTML we generate). We may need the apostrophe in some languages,
    # though.
    $config{example} = decode('utf8', $query->param('example'));
    if(!defined($config{example}) || $config{example} =~ m/^\s*$/)
    {
        $config{example} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{example} =~ s/^\s+//;
        $config{example} =~ s/\s+$//;
        $config{example} =~ s/\s+/ /sg;
        if($config{example} !~ m/^[\pL\pP ]+$/)
        {
            die "Example '$config{example}' contains characters other than letters, punctuation and space";
        }
        elsif($config{example} =~ m/[<>&"]/) # "
        {
            die "Example '$config{example}' contains less-than, greater-than, ampersand or the ASCII quote";
        }
        elsif($config{example} !~ m/\[\pL+\]/)
        {
            die "Example '$config{example}' does not contain a sequence of letters enclosed in [square brackets]";
        }
        if($config{example} =~ m/^(.+)$/)
        {
            $config{example} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # English translation of the example is provided if the current language is
    # not English. We can probably allow the same regular expressions as for
    # the original example, although we typically do not need non-English
    # letters in the English translation.
    $config{exampleen} = decode('utf8', $query->param('exampleen'));
    if(!defined($config{exampleen}) || $config{exampleen} =~ m/^\s*$/)
    {
        $config{exampleen} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{exampleen} =~ s/^\s+//;
        $config{exampleen} =~ s/\s+$//;
        $config{exampleen} =~ s/\s+/ /sg;
        if($config{exampleen} !~ m/^[\pL\pP ]+$/)
        {
            die "Example translation '$config{exampleen}' contains characters other than letters, punctuation and space";
        }
        elsif($config{exampleen} =~ m/[<>&"]/) # "
        {
            die "Example translation '$config{exampleen}' contains less-than, greater-than, ampersand or the ASCII quote";
        }
        if($config{exampleen} =~ m/^(.+)$/)
        {
            $config{exampleen} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # Comment is an optional English text. Since it may contain a word from the
    # language being documented, we should allow everything that is allowed in
    # the example.
    $config{comment} = decode('utf8', $query->param('comment'));
    if(!defined($config{comment}) || $config{comment} =~ m/^\s*$/)
    {
        $config{comment} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{comment} =~ s/^\s+//;
        $config{comment} =~ s/\s+$//;
        $config{comment} =~ s/\s+/ /sg;
        if($config{comment} !~ m/^[\pL\pP ]+$/)
        {
            die "Comment '$config{comment}' contains characters other than letters, punctuation and space";
        }
        elsif($config{comment} =~ m/[<>&"]/) # "
        {
            die "Comment '$config{comment}' contains less-than, greater-than, ampersand or the ASCII quote";
        }
        if($config{comment} =~ m/^(.+)$/)
        {
            $config{comment} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # The parameter 'save' comes from the Save button which submitted the form.
    $config{save} = decode('utf8', $query->param('save'));
    if(!defined($config{save}))
    {
        $config{save} = 0;
    }
    elsif($config{save} =~ m/^Save$/)
    {
        $config{save} = 1;
    }
    else
    {
        die "Unrecognized save button '$config{save}'";
    }
    return %config;
}



#------------------------------------------------------------------------------
# Reads the list of auxiliaries from an excerpt from the Python source code
# of the validator. This function is needed temporarily until we move the data
# to a separate JSON file.
#------------------------------------------------------------------------------
sub read_auxiliaries_from_python
{
    my %data;
    my $datafile = "$path/data.txt";
    # We need a buffer because some lists are spread across several lines.
    my $buffer = '';
    open(DATA, $datafile) or die("Cannot read '$datafile': $!");
    while(<DATA>)
    {
        # Remove the line break.
        s/\r?\n$//;
        # Skip comments.
        next if(m/^\s*\#/);
        s/\#.*//;
        $buffer .= $_;
        # A data line looks like this:
        # 'en':  ['be', 'have', 'do', 'will', 'would', 'may', 'might', 'can', 'could', 'shall', 'should', 'must', 'get', 'ought'],
        # Spaces are not interesting and line breaks can be harmful. Remove them.
        $buffer =~ s/\s//gs;
        if($buffer =~ m/'([a-z]{2,3})':\[('.+?'(?:,'.+?')*)\]/)
        {
            my $lcode = $1;
            my $auxlist = $2;
            if(!exists($lname_by_code{$lcode}))
            {
                die "Encountered unknown language code '$lcode' when reading the auxiliary list from Python";
            }
            my @auxlist = ();
            while($auxlist =~ s/^'(.+?)'//)
            {
                my $lemma = $1;
                push(@auxlist, $lemma);
                $auxlist =~ s/^\s*,\s*//;
            }
            # Create a record for each auxiliary. All fields that we want to
            # fill in the future are empty now, except for the lemma.
            my @recordlist = ();
            foreach my $lemma (@auxlist)
            {
                my %record =
                (
                    'lemma'       => $lemma,
                    'function'    => '',
                    'rule'        => '',
                    'example'     => '',
                    'exampleen'   => '',
                    'comment'     => '',
                    'status'      => 'undocumented',
                    'lastchanged' => '',
                    'lastchanger' => ''
                );
                push(@recordlist, \%record);
            }
            if(exists($data{$lcode}))
            {
                die("Duplicate auxiliary list for language '$lcode' in the Python source");
            }
            $data{$lcode} = \@recordlist;
            # Empty the buffer.
            ###!!! Ignore the possibility that a new list starts on the same line.
            $buffer = '';
        }
    }
    close(DATA);
    return %data;
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



#------------------------------------------------------------------------------
# Dumps the data as a JSON file.
#------------------------------------------------------------------------------
sub write_data_json
{
    # Initially, the data is read from the Python code.
    # This will change in the future and we will read the JSON file instead!
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl instead.",'."\n\n";
    $json .= '"auxiliaries": ['."\n";
    my @jsonrecords = ();
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        # Sort the list so that git diff is informative when we investigate changes.
        my @auxlist = sort {$a->{lemma} cmp $b->{lemma}} (@{$data->{$lcode}});
        foreach my $aux (@auxlist)
        {
            my @record =
            (
                ['lcode'       => $lcode],
                ['lemma'       => $aux->{lemma}],
                ['function'    => $aux->{function}],
                ['rule'        => $aux->{rule}],
                ['example'     => $aux->{example}],
                ['exampleen'   => $aux->{exampleen}],
                ['comment'     => $aux->{comment}],
                ['status'      => $aux->{status}],
                ['lastchanged' => $aux->{lastchanged}],
                ['lastchanger' => $aux->{lastchanger}]
            );
            push(@jsonrecords, encode_json(@record));
        }
    }
    $json .= join(",\n", @jsonrecords)."\n";
    $json .= "]}\n";
    open(JSON, ">$filename") or die("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
    # Commit the changes to the repository and push them to Github.
    system('/home/zeman/bin/git-push-docs-automation.sh');
}



#------------------------------------------------------------------------------
# Takes a list of pairs [name, value] and returns the corresponding JSON
# structure {"name1": "value1", "name2": "value2"}. The pair is an arrayref;
# if there is a third element in the array and it says "numeric", then the
# value is treated as numeric, i.e., it is not enclosed in quotation marks.
# The type in the third position can be also "list of structures" and
# "list of numeric".
#------------------------------------------------------------------------------
sub encode_json
{
    my @json = @_;
    # Encode JSON.
    my @json1 = ();
    foreach my $pair (@json)
    {
        my $name = '"'.$pair->[0].'"';
        my $value;
        if(defined($pair->[2]))
        {
            if($pair->[2] eq 'numeric')
            {
                $value = $pair->[1];
            }
            elsif($pair->[2] eq 'list')
            {
                # Assume that each list element is a string.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    my $element_json = $element;
                    $element_json = escape_json_string($element_json);
                    $element_json = '"'.$element_json.'"';
                    push(@array_json, $element_json);
                }
                $value = '['.join(', ', @array_json).']';
            }
            elsif($pair->[2] eq 'list of numeric')
            {
                # Assume that each list element is numeric.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    push(@array_json, $element);
                }
                $value = '['.join(', ', @array_json).']';
            }
            elsif($pair->[2] eq 'list of structures')
            {
                # Assume that each list element is a structure.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    my $element_json = encode_json(@{$element});
                    push(@array_json, $element_json);
                }
                $value = '['.join(', ', @array_json).']';
            }
            else
            {
                log_fatal("Unknown value type '$pair->[2]'.");
            }
        }
        else # value is a string
        {
            if(!defined($pair->[1]))
            {
                log_warn("Unknown value of attribute '$name'.");
            }
            $value = $pair->[1];
            $value = escape_json_string($value);
            $value = '"'.$value.'"';
        }
        push(@json1, "$name: $value");
    }
    my $json = '{'.join(', ', @json1).'}';
    return $json;
}



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
