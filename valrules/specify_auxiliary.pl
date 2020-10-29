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
my $lcode = $query->param('lcode');
my $lemma = $query->param('lemma');
# Variables with the data from the form are tainted. Running them through a regular
# expression will untaint them and Perl will allow us to use them.
if ( !defined($lcode) || $lcode =~ m/^\s*$/ )
{
    $lcode = '';
}
elsif ( $lcode =~ m/^([a-z]{2,3})$/ )
{
    $lcode = $1;
    if(!exists($lname_by_code{$lcode}))
    {
        die "Unknown language code '$lcode'";
    }
}
else
{
    die "Language code '$lcode' does not consist of two or three lowercase English letters";
}
if ( !defined($lemma) || $lemma =~ m/^\s*$/ )
{
    $lemma = '';
}
elsif ( $lemma =~ m/^\s*(\pL+)\s*$/ )
{
    $lemma = $1;
}
else
{
    die "Lemma '$lemma' contains non-letter characters";
}
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
if($lcode eq '')
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
        print(join(', ', map {"<img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" />&nbsp;<a href=\"specify_auxiliary.pl?lcode=$languages->{$_}{lcode}\">$_</a>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit auxiliaries of that language.
else
{
    # Read the data file.
    my @data = read_auxiliaries_from_python();
    my @mydata = grep {$_->{lcode} eq $lcode} (@data);
    # It is possible that there are no auxiliaries for my language so far.
    # However, there must not be multiple entries for the same language.
    if(scalar(@mydata)>1)
    {
        die "There are ".scalar(@mydata)." entries for language '$lcode' in the current database of auxiliaries";
    }
    my @myauxlist = ();
    if(scalar(@mydata)==1)
    {
        @myauxlist = @{$mydata[0]{auxlist}};
    }
    print <<EOF
  <h1>Specify auxiliaries for $lname_by_code{$lcode}</h1>
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
    equivalents of “to become, to look like, to be called” etc. are not copulas
    in UD, even if a traditional grammar classifies them as such. In UD they
    should head an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    relation instead. A copula is normally tagged <a href="https://universaldependencies.org/u/pos/AUX_.html">AUX</a>.
    Exception: in some languages a personal or demonstrative pronoun /
    determiner can be used as a copula and then we keep it tagged
    <a href="https://universaldependencies.org/u/pos/PRON.html">PRON</a> or
    <a href="https://universaldependencies.org/u/pos/DET.html">DET</a>.</p>
EOF
    ;
    if($lemma eq '')
    {
        my $n = scalar(@myauxlist);
        if($n > 0)
        {
            print("  <h2 style='color:red'>You have $n undocumented auxiliaries!</h2>\n");
            print("  <p>Please edit each undocumented auxiliary and supply the missing information.</p>\n");
            print("  <p>".join(' ', map {my $l = $_; $l =~ s/\PL//g; $l = 'XXX' if($l eq ''); "<a href=\"specify_auxiliary.pl?lcode=$lcode&amp;lemma=$l\">$l</a>"} (@myauxlist))."</p>\n");
        }
    }
    else
    {
        print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
  <table>
    <tr>
      <td>Lemma</td>
      <td>Function</td>
      <td>Rule<br/>
        <small>e.g. “combination of the auxiliary and a past participle of the main verb”</small>
      </td>
      <td>Example<br/>
        <small>mark the auxiliary by enclosing it in square brackets, e.g., “he [has] done it”</small>
      </td>
      <td>English translation of the example</td>
      <td>Comment</td>
    </tr>
    <tr>
      <td><input name=lemma type=text /></td>
      <td>
        <select name=function>
          <option>-----</option>
          <option>Copula</option>
          <option>Periphrastic aspect: perfect</option>
          <option>Periphrastic aspect: progressive</option>
          <option>Periphrastic tense: past</option>
          <option>Periphrastic tense: future</option>
          <option>Periphrastic voice: passive</option>
          <option>Periphrastic voice: causative</option>
          <option>Periphrastic mood: conditional</option>
          <option>Periphrastic mood: imperative</option>
          <option>Needed in negative clauses (like English <i>do</i>)</option>
          <option>Needed in interrogative clauses (like English <i>do</i>)</option>
          <option>Modal auxiliary: necessitative <i>(must, should)</i></option>
          <option>Modal auxiliary: potential <i>(can, might)</i></option>
        </select>
      </td>
      <td><input name=rule type=text /></td>
      <td><input name=example type=text /></td>
      <td><input name=exampleen type=text /></td>
      <td><input name=comment type=text /></td>
    </tr>
  </table>
  <input name=save type=submit value="Save" />
  </form>
EOF
        ;
    }
    # Print the data on the web page.
    print("  <h2>Known auxiliaries for this and other languages</h2>\n");
    print("  <table>\n");
    print("    <tr><th colspan=2>Language</th><th>Total</th><th>Lemmas</th></tr>\n");
    # First display the actual language.
    # Then display languages from the same family and genus.
    # Then languages from the same family but different genera.
    # Then all remaining languages.
    my $myfamilygenus = $languages->{$lname_by_code{$lcode}}{familygenus};
    my $myfamily = $languages->{$lname_by_code{$lcode}}{family};
    my $mygenus = $languages->{$lname_by_code{$lcode}}{genus};
    foreach my $row (@data)
    {
        next unless($row->{lcode} eq $lcode);
        my $n = scalar(@{$row->{auxlist}});
        print("    <tr><td>$lname_by_code{$row->{lcode}}</td><td>$row->{lcode}</td><td>$n</td><td>".join(' ', @{$row->{auxlist}})."</td></tr>\n");
        last;
    }
    foreach my $row (@data)
    {
        next if($row->{lcode} eq $lcode);
        next unless($languages->{$lname_by_code{$row->{lcode}}}{familygenus} eq $myfamilygenus);
        my $n = scalar(@{$row->{auxlist}});
        print("    <tr><td>$lname_by_code{$row->{lcode}}</td><td>$row->{lcode}</td><td>$n</td><td>".join(' ', @{$row->{auxlist}})."</td></tr>\n");
    }
    foreach my $row (@data)
    {
        next if($languages->{$lname_by_code{$row->{lcode}}}{familygenus} eq $myfamilygenus);
        next unless($languages->{$lname_by_code{$row->{lcode}}}{family} eq $myfamily);
        my $n = scalar(@{$row->{auxlist}});
        print("    <tr><td>$lname_by_code{$row->{lcode}}</td><td>$row->{lcode}</td><td>$n</td><td>".join(' ', @{$row->{auxlist}})."</td></tr>\n");
    }
    foreach my $row (@data)
    {
        next if($languages->{$lname_by_code{$row->{lcode}}}{family} eq $myfamily);
        my $n = scalar(@{$row->{auxlist}});
        print("    <tr><td>$lname_by_code{$row->{lcode}}</td><td>$row->{lcode}</td><td>$n</td><td>".join(' ', @{$row->{auxlist}})."</td></tr>\n");
    }
    print("  </table>\n");
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Reads the list of auxiliaries from an excerpt from the Python source code
# of the validator. This function is needed temporarily until we move the data
# to a separate JSON file.
#------------------------------------------------------------------------------
sub read_auxiliaries_from_python
{
    my @data;
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
            push(@data, {'lcode' => $lcode, 'auxlist' => \@auxlist});
            # Empty the buffer.
            ###!!! Ignore the possibility that a new list starts on the same line.
            $buffer = '';
        }
    }
    close(DATA);
    return @data;
}
