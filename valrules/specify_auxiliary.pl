#!/usr/bin/perl -wT

use strict;
use utf8;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
#binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use open ':utf8';
use Encode;

# Path to the data on the web server.
my $path = '/home/zeman/unidep/docs-automation/valrules';
# We must set our own PATH even if we do not depend on it.
# The system call may potentially use it, and the one from outside is considered insecure.
$ENV{'PATH'} = $path.':/home/zeman/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
# Print the output.
my $query = new CGI;
$query->charset('utf-8'); # makes the charset explicitly appear in the headers
print($query->header());
print <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify auxiliaries in UD</title>
  <style type="text/css"> img {border: none;} </style>
</head>
<body>
  <h1>Specify auxiliaries for English</h1>
  <p><strong>Remember:</strong> Not everything that a traditional grammar labels
    as auxiliary is necessarily an <a href="https://universaldependencies.org/u/pos/AUX_.html">auxiliary in UD</a>.
    Just because a verb combines with another verb does not necessarily mean
    that one of the verbs is auxiliary; the usual alternative in UD is treating
    one of the verbs as an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    of the other. Language-specific tests whether a verb is auxiliary are
    grammatical rather than semantic: just because something has a modal or
    near-modal meaning does not mean that it is an auxiliary, and in some
    languages modal verbs do not count as auxiliaries at all. Some verbs
    function as auxiliaries in some constructions and as full verbs in others
    (e.g., <i>to have</i> in English). There are also auxiliaries whose nature
    is completely different from verbs in the given language.</p>
  <form>
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
# Read the data file.
my @data;
my $datafile = "$path/data.txt";
open(DATA, $datafile) or die("Cannot read '$datafile': $!");
# For a start, the data file contains a copy of the lines from the Python source of the validator.
while(<DATA>)
{
    # Remove the line break.
    s/\r?\n$//;
    # Skip comments.
    next if(m/^\s*\#/);
    # A data line looks like this:
    # 'en':  ['be', 'have', 'do', 'will', 'would', 'may', 'might', 'can', 'could', 'shall', 'should', 'must', 'get', 'ought'],
    # It could use different syntax and the entry could even be split into
    # multiple lines but we ignore such possibilities for now.
    if(m/'([a-z]{2,3})':\s*\[\s*('.+?'(?:\s*,\s*'.+?')*)\s*\]/)
    {
        my $lcode = $1;
        my $auxlist = $2;
        my @auxlist = ();
        while($auxlist =~ s/^'(.+?)'//)
        {
            my $lemma = $1;
            push(@auxlist, $lemma);
            $auxlist =~ s/^\s*,\s*//;
        }
        push(@data, {'lcode' => $lcode, 'auxlist' => \@auxlist});
    }
}
close(DATA);
# Print the data on the web page.
print("  <h2>Known auxiliaries for this and other languages</h2>\n");
print("  <table>\n");
print("    <tr><th>Language</th><th>Lemmas</th></tr>\n");
foreach my $row (@data)
{
    print("    <tr><td>$row->{lcode}</td><td>".join(' ', @{$row->{auxlist}})."</td></tr>\n");
}
print("  </table>\n");
print <<EOF
</body>
</html>
EOF
;
