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
my @cases = ('nom', 'gen', 'par', 'dat', 'acc', 'ins', 'loc', 'ill');
my @functions =
(
    # Indent level in hierarchy; Verbose description; Case short code
    [0, 'Location (locative)',                                                  'Loc'],
     [1, 'In/surface/out', undef], # (we want to display this comment but not to make it selectable)
      [2, 'Inside something (“in”, inessive)',                                  'Ine'],
      [2, 'At a point, on the border of something (“at, on”, adessive)',        'Ade'],
      [2, 'Outside something (“outside, out of, off”)',                         'Out'],
     [1, 'X axis', undef], # (we want to display this comment but not to make it selectable)
      [2, 'Beside something (“beside, aside, alongside, next to”, apudessive)', 'Apu'],
     [1, 'Y axis', undef], # (we want to display this comment but not to make it selectable)
      [2, 'Above or atop something (“above, atop”, superessive)',               'Sup'],
      [2, 'Below something (“below, beneath, under”, subessive)',               'Sub'],
     [1, 'Z axis', undef], # (we want to display this comment but not to make it selectable)
      [2, 'In front of something (“in front of”)',                              'Frt'],
      [2, 'Behind something (“behind, beyond, past”, postessive)',              'Pst'],
     [1, 'Near location (“near”, proximative)',                                 'Prx'],
     [1, 'Far from location (“far from”, distantive)',                          'Dst'],
     [1, 'Around something (“around, round”)',                                  'Rnd'],
     [1, 'Opposite something (“opposite”)',                                     'Opp'],
     [1, 'Across something (“across”)',                                         'Crs'],
     [1, 'Along something (“along”)',                                           'Lng'],
     [1, 'Between two or more points (“between, among, amid”, intrative)',      'Int'],
     [1, 'Spread in an area (“throughout, over”)',                              'Tot'],
    [0, 'Direction (directional)',                                              'Dir'],
     [1, 'Focused on origin (“from”, ablative)',                                'Abl'],
      [2, 'Origin inside something (elative)',                                  'Ela'], # Wikipedia also lists inelative (INEL) but does not show the difference
      [2, 'Origin on the surface of something (“off”, delative)',               'Del'],
      [2, 'Origin atop or above something (“from above”, superelative)',        'Spe'],
      [2, 'Origin under or below something (“from under”, subelative)',         'Sbe'],
      [2, 'Origin behind something (“from behind”, postelative)',               'Pse'],
      [2, 'Origin between something (“from between”, intraelative)',            'Ite'],
     [1, 'Focused on path (“through, via”, perlative)',                         'Per'],
      [2, 'Ascending path (“up”)',                                              'Pup'],
      [2, 'Descending path (“down”)',                                           'Pdn'],
     [1, 'Focused on target (“to”, lative)',                                    'Lat'],
      [2, 'Target inside something (“into”, illative)',                         'Ill'],
      [2, 'Target atop or above something (“onto”, superlative)',               'Spl'],
      [2, 'Target under or below something (“to under”, sublative)',            'Sbl'],
      [2, 'Target in front of something (“in front of, before”)',               'Frl'],
      [2, 'Target behind something (“behind, beyond”, postlative)',             'Psl'],
    [0, 'Time (temporal)',                                                      'Tem'],
     [1, 'Before a point (“before, prior to, till, until”, antessive)',         'Ant'],
     [1, 'Around a point (“around, circa”)',                                    'Trd'],
     [1, 'At a point or period (“at, on, in, upon”)',                           'Tat'],
     [1, 'During a period (“during, over, for, within, whilst”)',               'Tdg'],
     [1, 'After a point or period (“after, since, from, following”)',           'Tps'],
     [1, 'Between two points (“between”)',                                      'Tbt'],
    [0, 'Of/with/without', undef], # (we want to display this comment but not to make it selectable)
     [1, 'Complement/attribute (“that”)',                                       'Atr'],
     [1, 'Belonging to, composed of something (“of”, genitive)',                'Gen'],
     [1, 'Per something (“per”, distributive)',                                 'Dis'],
     [1, 'Together with something (“with”, comitative)',                        'Com'],
     [1, 'Without something (“without”, abessive)',                             'Abe'],
     [1, 'Including something (“including”)',                                   'Inc'],
     [1, 'Besides something (“besides, in addition to”)',                       'Bes'],
     [1, 'Except something (“except”)',                                         'Exc'],
     [1, 'Instead of something (“instead of, rather than”)',                    'Isd'],
    [0, 'Like/unlike', undef], # (we want to display this comment but not to make it selectable)
     [1, 'Temporary state (“as”, essive)',                                      'Ess'],
     [1, 'Same as something (equative)',                                        'Equ'],
     [1, 'Similar to something (“like”, semblative)',                           'Sem'],
     [1, 'Dissimilar to something (“unlike, as opposed to”, dissemblative)',    'Dsm'],
     [1, 'Better/worse/other than something (“than”, comparative)',             'Cmp'],
     [1, 'Difference (“by how much”)',                                          'Dif'],
     [1, 'Comment (“whereas”)',                                                 'Cmt'], # I would argue that 'whereas' should be CCONJ but it is tagged SCONJ in the English corpora.
    [0, 'Cause/consequence/circumstance', undef], # (we want to display this comment but not to make it selectable)
     [1, 'Cause or purpose (“because of, due to, in order to”, causative)',     'Cau'],
     [1, 'Taking circumstance into account (“given, considering, per”)',        'Cns'],
     [1, 'Ignoring circumstance (“regardless”)',                                'Rls'],
     [1, 'Concession (“despite, notwithstanding”)',                             'Ccs'],
     [1, 'Condition (“depending on, in case of”)',                              'Dep'],
     [1, 'Topic (“about, concerning, regarding, as for, as to”)',               'Tpc'],
     [1, 'Source of information (“according to”)',                              'Src'],
     [1, 'Passive agent (“by”)',                                                'Agt'],
     [1, 'Instrument (“with”, instrumental)',                                   'Ins'],
     [1, 'Beneficiary (“for”, benefactive)',                                    'Ben'],
     [1, 'Adversary (“against”, adversative)',                                  'Adv'],
    [0, 'Paratactic relation (to be used with conj)', undef], # (we want to display this comment but not to make it selectable)
     [1, 'Conjunction (“and”)',                                                'Conj'],
     [1, 'Negative conjunction (“neither … nor”)',                             'Nnor'],
     [1, 'Disjunction (“or”)',                                                 'Disj'],
     [1, 'Adversative (“but, yet”)',                                           'Advs'],
     [1, 'Inferential-reason (“for”)',                                         'Reas'],
     [1, 'Inferential-consequence (“so”)',                                     'Cnsq']
);
# Sanity check: Did I specify a unique code for each function?
my %fdesc;
foreach my $f (@functions)
{
    if(defined($f->[2]))
    {
        if(exists($fdesc{$f->[2]}))
        {
            die("Ambiguous function code '$f->[2]':\noriginally used for $fdesc{$f->[2]}\nnow used for $f->[1]\n");
        }
        $fdesc{$f->[2]} = $f->[1];
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
my %config = get_parameters($query, \%lname_by_code, \@functions);
$query->charset('utf-8'); # makes the charset explicitly appear in the headers
print($query->header());
print <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify enhanced deprels in UD</title>
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
    print("  <h1>Specify enhanced dependency relations for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_edeprel.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit edeprels of that language.
else
{
    # Read the data file from JSON.
    my $data = read_edeprels_json($path);
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
        process_form_data(\%data, $query, \@cases, \@functions);
    }
    # If we are not saving but have received an edeprel, it means the edeprel should be edited.
    elsif($config{edeprel} ne '')
    {
        summarize_guidelines();
        print_edeprel_details(\%data);
        if(exists($data{$config{lcode}}{$config{edeprel}}))
        {
            print_edeprel_form(\%data, \@cases, \@functions);
        }
        print_all_edeprels(\%data, $languages, \@functions);
    }
    elsif($config{add})
    {
        summarize_guidelines();
        print_edeprel_form(\%data, \@cases, \@functions);
        print_all_edeprels(\%data, $languages, \@functions);
    }
    else
    {
        summarize_guidelines();
        print_edeprels_for_language(\%data);
        print_all_edeprels(\%data, $languages, \@functions);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of edeprels permitted in the current language.
#------------------------------------------------------------------------------
sub print_edeprels_for_language
{
    my $data = shift;
    print("  <h2>Case markers for enhanced deprels</h2>\n");
    if(exists($data->{$config{lcode}}))
    {
        my $ldata = $data->{$config{lcode}};
        my @edeprels = sort(keys(%{$ldata}));
        if(scalar(@edeprels) > 0)
        {
            print("  <p>".join(', ', map {"<a href=\"specify_edeprel.pl?lcode=$config{lcode}&amp;edeprel=$_\">$_</a>"} (@edeprels))."</p>\n");
        }
        else
        {
            print("  <p>No case enhancements have been specified so far.</p>\n");
        }
    }
    else
    {
        print("  <p>No case enhancements have been specified so far.</p>\n");
    }
    print("  <form action=\"specify_edeprel.pl\" method=\"post\" enctype=\"multipart/form-data\">\n");
    print("    <input name=lcode type=hidden value=\"$config{lcode}\" />\n");
    print("    <input name=ghu type=hidden value=\"$config{ghu}\" />\n");
    print("    <input name=add type=submit value=\"Add\" />\n");
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Prints information about a given edeprel in a given language.
#------------------------------------------------------------------------------
sub print_edeprel_details
{
    my $data = shift;
    if(exists($data->{$config{lcode}}))
    {
        print("  <h2>$config{edeprel}</h2>\n");
        if(exists($data->{$config{lcode}}{$config{edeprel}}))
        {
            my $fdata = $data->{$config{lcode}}{$config{edeprel}};
            # There is nothing more to do here. The actual details will be shown in the form.
        }
        else
        {
            die("No information about case enhancement '$config{edeprel}' in language '$config{lcode}'");
        }
    }
    else
    {
        die("No case enhancements have been specified so far for language '$config{lcode}'");
    }
}



#------------------------------------------------------------------------------
# Prints the form where a particular edeprel can be edited.
#------------------------------------------------------------------------------
sub print_edeprel_form
{
    my $data = shift;
    my $cases = shift;
    my $functions = shift;
    unless($config{add})
    {
        if($config{edeprel} eq '')
        {
            die("Unknown edeprel");
        }
        if(!exists($data->{$config{lcode}}{$config{edeprel}}))
        {
            die("Case enhancement '$config{edeprel}' not found in language '$config{lcode}'");
        }
    }
    my $show_exampleen = $config{lcode} ne 'en';
    my $hedeprel = htmlescape($config{edeprel});
    my $hlanguage = htmlescape($lname_by_code{$config{lcode}});
    print("  <h3>Specify the possible functions of $hedeprel</h3>\n");
    print <<EOF
  <form action="specify_edeprel.pl" method="post" enctype="multipart/form-data">
  <input name=lcode type=hidden value="$config{lcode}" />
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
    print("  <input name=origedeprel type=hidden size=10 value=\"$hedeprel\" />\n");
    my $hlex = htmlescape($data->{$config{lcode}}{$config{edeprel}}{lex});
    print("  <strong>Lexical marker:</strong> <input name=lex type=text size=10 value=\"$hlex\" />\n");
    my $morphoptions = join('', map {my $s = $_ eq $data->{$config{lcode}}{$config{edeprel}}{morph} ? ' selected' : ''; "<option$s>$_</option>"} ('', @{$cases}));
    print("  <strong>Morphological marker:</strong> <select name=morph>$morphoptions</select>\n");
    print("  <strong>Can be used with:</strong>\n");
    my %extchecked;
    foreach my $deprel (@{$data->{$config{lcode}}{$config{edeprel}}{extends}})
    {
        $extchecked{$deprel} = ' checked';
    }
    print("  <input type=\"checkbox\" id=\"extobl\"   name=\"extobl\"   value=\"1\"$extchecked{obl} />&nbsp;<tt>obl</tt>\n");
    print("  <input type=\"checkbox\" id=\"extnmod\"  name=\"extnmod\"  value=\"1\"$extchecked{nmod} />&nbsp;<tt>nmod</tt>\n");
    print("  <input type=\"checkbox\" id=\"extadvcl\" name=\"extadvcl\" value=\"1\"$extchecked{advcl} />&nbsp;<tt>advcl</tt>\n");
    print("  <input type=\"checkbox\" id=\"extacl\"   name=\"extacl\"   value=\"1\"$extchecked{acl} />&nbsp;<tt>acl</tt>\n");
    print("  <input type=\"checkbox\" id=\"extconj\"  name=\"extconj\"  value=\"1\"$extchecked{conj} />&nbsp;<tt>conj</tt>\n");
    print("  <table>\n");
    print("    <tr id=\"inputheader\">\n");
    print("      <td>Function</td>\n");
    print("      <td>Example</td>\n");
    if($show_exampleen)
    {
        print("      <td>English translation of the example</td>\n");
    }
    print("      <td>Comment</td>\n");
    print("    </tr>\n");
    print("    <tr id=\"inputhints\">\n");
    print("      <td></td>\n");
    print("      <td><small>Mark the cased part by enclosing it in square brackets, e.g., “He is [in the house].”</small></td>\n");
    if($show_exampleen)
    {
        print("      <td></td>\n");
    }
    print("      <td></td>\n");
    print("    </tr>\n");
    # Collect the current function codes of the current case marker.
    my %curfunctions;
    foreach my $f (@{$data->{$config{lcode}}{$config{edeprel}}{functions}})
    {
        $curfunctions{$f->{function}} = $f;
    }
    foreach my $f (@{$functions})
    {
        print("    <tr>\n");
        # Distinguish real functions from uncheckable comments.
        my $isfunction = defined($f->[2]);
        my $indent = '&nbsp;&nbsp;&nbsp;&nbsp;' x $f->[0];
        if($isfunction)
        {
            my $checked = '';
            my $hexample = '';
            my $hexampleen = '';
            my $hcomment = '';
            if(exists($curfunctions{$f->[2]}))
            {
                $checked = ' checked';
                $hexample = htmlescape($curfunctions{$f->[2]}{example});
                $hexampleen = htmlescape($curfunctions{$f->[2]}{exampleen});
                $hcomment = htmlescape($curfunctions{$f->[2]}{comment});
            }
            my $checkbox = "<input type=\"checkbox\" id=\"func$f->[2]\" name=\"func$f->[2]\" value=\"1\"$checked />";
            print("      <td>$indent$checkbox$f->[1]</td>\n");
            print("      <td><input name=example$f->[2] type=text size=50 value=\"$hexample\" /></td>\n");
            if($show_exampleen)
            {
                print("      <td><input name=exampleen$f->[2] type=text size=50 value=\"$hexampleen\" /></td>\n");
            }
            print("      <td><input name=comment$f->[2] type=text value=\"$hcomment\" /></td>\n");
        }
        else # no form controls for uncheckable comments
        {
            print("      <td>$indent$f->[1]</td>\n");
            print("      <td></td>\n");
            if($show_exampleen)
            {
                print("      <td></td>\n");
            }
            print("      <td></td>\n");
        }
        print("    </tr>\n");
    }
    print("  </table>\n");
    print("  <input name=save type=submit value=\"Save\" />\n");
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Processes data submitted from a form and prints confirmation or an error
# message.
# We are processing a Save request after an edeprel was edited.
# We have briefly checked that the parameters match expected regular expressions.
# Nevertheless, only now we can also report an error if a parameter is empty.
#------------------------------------------------------------------------------
sub process_form_data
{
    my $data = shift;
    my $query = shift;
    my $cases = shift;
    my $functions = shift;
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
    # The user can edit lexical and morphological case markers separately.
    # Combine them into one marker now.
    if($config{lex} ne '' && $config{morph} ne '')
    {
        $config{edeprel} = $config{lex}.':'.$config{morph};
    }
    elsif($config{lex} ne '')
    {
        $config{edeprel} = $config{lex};
    }
    elsif($config{morph} ne '')
    {
        $config{edeprel} = $config{morph};
    }
    else
    {
        $config{edeprel} = '';
    }
    # Save the basic deprels that can be enhanced with this case marker.
    my @extends = ();
    # Save the functions of this case marker.
    my @newfunctions = ();
    if($config{edeprel} ne '')
    {
        print("    <li>edeprel = '$config{edeprel}'</li>\n");
        # If there is no origedeprel, we are adding a new edeprel.
        # If there is origedeprel and it is different from edeprel, we are renaming the edeprel.
        # If there is origedeprel and it matches edeprel, we are editing the edeprel without renaming it.
        if($config{origedeprel} ne '')
        {
            if(exists($data->{$config{lcode}}{$config{origedeprel}}))
            {
                if($config{edeprel} ne $config{origedeprel})
                {
                    if(exists($data->{$config{lcode}}{$config{edeprel}}))
                    {
                        print("    <li style='color:red'>ERROR: Cannot rename enhanced dependency relation '$config{origedeprel}' to '$config{edeprel}' because the target relation already exists</li>\n");
                        $error = 1;
                    }
                    else
                    {
                        $data->{$config{lcode}}{$config{edeprel}} = $data->{$config{lcode}}{$config{origedeprel}};
                        delete($data->{$config{lcode}}{$config{origedeprel}});
                    }
                }
            }
            else
            {
                print("    <li style='color:red'>ERROR: Unknown enhanced dependency relation '$config{origedeprel}' in language '$config{language}' cannot be renamed to '$config{edeprel}'</li>\n");
                $error = 1;
            }
        }
        print("    <li>lex = '$config{lex}'</li>\n");
        print("    <li>morph = '$config{morph}'</li>\n");
        my $casesre = join('|', @{$cases});
        if($config{morph} ne '' && $config{morph} !~ m/^($casesre)$/)
        {
            print("    <li style='color:red'>ERROR: Unknown morphological marker '$config{morph}'</li>\n");
            $error = 1;
        }
        my %extends;
        foreach my $deprel (@{$data->{$config{lcode}}{$config{edeprel}}{extends}})
        {
            $extends{$deprel} = 1;
        }
        # Count the checked deprels. Separately: subordinating deprels (nmod, obl, acl, advcl) and coordinating deprels (conj).
        my $nsdeprels = 0;
        my $ncdeprels = 0;
        foreach my $deprel (qw(obl nmod advcl acl conj))
        {
            if($config{'ext'.$deprel})
            {
                if($deprel eq 'conj')
                {
                    $ncdeprels++;
                }
                else
                {
                    $nsdeprels++;
                }
                if($extends{$deprel})
                {
                    print("    <li>No change: still permitted with '$deprel'</li>\n");
                }
                else
                {
                    print("    <li style='color:blue'>Now permitted with '$deprel'</li>\n");
                }
                push(@extends, $deprel);
            }
            else
            {
                if($extends{$deprel})
                {
                    print("    <li style='color:purple'>No longer permitted with '$deprel'</li>\n");
                }
                else
                {
                    print("    <li>No change: still not permitted with '$deprel'</li>\n");
                }
            }
        }
        if($nsdeprels+$ncdeprels==0)
        {
            print("    <li style='color:red'>ERROR: At least one basic deprel must be allowed</li>\n");
            $error = 1;
        }
        my %curfunctions;
        foreach my $f (@{$data->{$config{lcode}}{$config{edeprel}}{functions}})
        {
            $curfunctions{$f->{function}} = $f;
        }
        # Count the checked functions. Separately: subordinating functions (nmod, obl, acl, advcl) and coordinating functions (conj).
        my $nsfunctions = 0;
        my $ncfunctions = 0;
        foreach my $f (@{$functions})
        {
            my $fcode = $f->[2];
            my $ename = 'example'.$fcode;
            my $eename = 'exampleen'.$fcode;
            my $cname = 'comment'.$fcode;
            if($config{'func'.$fcode})
            {
                # Hack: coordinating functions have four-letter codes, subordinating three.
                if(length($fcode)>3)
                {
                    $ncfunctions++;
                }
                else
                {
                    $nsfunctions++;
                }
                if($curfunctions{$fcode})
                {
                    print("    <li>No change: still has the function '$fcode': '$f->[1]'</li>\n");
                }
                else
                {
                    print("    <li style='color:blue'>Now has the function '$fcode': '$f->[1]'</li>\n");
                }
                if($config{$ename})
                {
                    print("    <li>Example = '".htmlescape($config{$ename})."'</li>\n");
                }
                else
                {
                    print("    <li style='color:red'>ERROR: Missing example of '$fcode'</li>\n");
                    $error = 1;
                }
                if($config{$eename})
                {
                    print("    <li>Example = '".htmlescape($config{$eename})."'</li>\n");
                }
                elsif($config{lcode} ne 'en')
                {
                    print("    <li style='color:red'>ERROR: Missing English translation of the example of '$fcode'</li>\n");
                    $error = 1;
                }
                if($config{$cname} ne '')
                {
                    print("    <li>Comment = '".htmlescape($config{$cname})."'</li>\n");
                }
                push(@newfunctions, {'function' => $fcode, 'example' => $config{$ename}, 'exampleen' => $config{$eename}, 'comment' => $config{$cname}});
            }
            else
            {
                if($curfunctions{$fcode})
                {
                    print("    <li style='color:purple'>No longer has the function '$fcode': '$f->[1]'</li>\n");
                }
                if($config{$ename})
                {
                    print("    <li style='color:red'>ERROR: Example '".htmlescape($config{$ename})."' cannot be accepted when the function '$fcode' is not turned on</li>\n");
                    $error = 1;
                }
                if($config{$eename})
                {
                    print("    <li style='color:red'>ERROR: Example '".htmlescape($config{$eename})."' cannot be accepted when the function '$fcode' is not turned on</li>\n");
                    $error = 1;
                }
                if($config{$cname})
                {
                    print("    <li style='color:red'>ERROR: Comment '".htmlescape($config{$cname})."' cannot be accepted when the function '$fcode' is not turned on</li>\n");
                    $error = 1;
                }
            }
        }
        if($nsdeprels>0 && $nsfunctions==0)
        {
            print("    <li style='color:red'>ERROR: At least one subordinating function and example must be provided if 'nmod/obl/acl/advcl' is allowed</li>\n");
            $error = 1;
        }
        if($ncdeprels>0 && $ncfunctions==0)
        {
            print("    <li style='color:red'>ERROR: At least one coordinating function and example must be provided if 'conj' is allowed</li>\n");
            $error = 1;
        }
        if($ncdeprels>0 && $config{morph} ne '')
        {
            print("    <li style='color:red'>ERROR: Morphological case markers are not expected with 'conj'</li>\n");
            $error = 1;
        }
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing edeprel</li>\n");
        $error = 1;
    }
    print("  </ul>\n");
    if($error)
    {
        print("  <p style='color:red'><strong>WARNING:</strong> Nothing was saved because there were errors.</p>\n");
    }
    else
    {
        my $ddata = $data->{$config{lcode}}{$config{edeprel}};
        # Do I want to use my local time or universal time in the timestamps?
        #my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = localtime(time());
        my $timestamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 1900+$year, 1+$mon, $mday, $hour, $min, $sec);
        $ddata->{lastchanged} = $timestamp;
        $ddata->{lastchanger} = $config{ghu};
        $ddata->{lex} = $config{lex};
        $ddata->{morph} = $config{morph};
        $ddata->{extends} = \@extends;
        $ddata->{functions} = \@newfunctions;
        write_edeprels_json($data, "$path/edeprels.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_edeprel.pl" method="post" enctype="multipart/form-data">
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
    # cat UD_English-{PUD,EWT,GUM}/*.conllu | udapy -T util.Filter mark=1 keep_tree_if_node='len(node.deps)>=1 and "advcl:if" in [x["deprel"] for x in node.deps]' | less -R
    # This is faster because it can process the first file immediately after reading it:
    # ( udapy -T read.Conllu files="`echo UD_Czech-{PUD,PDT,FicTree,CAC,CLTT}/*.conllu`" util.Filter mark=1 keep_tree_if_node='len(node.deps)>=1 and "advcl:aby" in [x["deprel"] for x in nodeeps]' | less -R ) 2>/dev/null
    print <<EOF
  <h1><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$lname_by_code{$config{lcode}}}{flag}.png\" />
    Specify enhanced dependency relations for $lname_by_code{$config{lcode}}</h1>
  <p>The <a href="https://universaldependencies.org/u/overview/enhanced-syntax.html">guidelines
    for enhanced dependencies</a> say that certain dependency relations (such
    as <tt><a href="https://universaldependencies.org/u/dep/obl.html">obl</a></tt>
    or <tt><a href="https://universaldependencies.org/u/dep/nmod.html">nmod</a></tt>)
    can be enhanced to explicitly show the case marker of the dependent nominal.
    The case marker can be lexical (typically corresponding to a lemma of an
    adposition), morphological (corresponding to a value of the
    <tt><a href="https://universaldependencies.org/u/feat/Case.html">Case</a></tt>
    feature), or a combination of both. The official UD validator will accept
    case markers that are documented here.</p>
  <!--p><a href="https://udapi.github.io/">Udapi</a> can be used to find examples
    of enhanced dependency relation like this:
    <pre>cat UD_English-{PUD,EWT,GUM}/*.conllu | udapy -T util.Filter mark=1 keep_tree_if_node='len(node.deps)&gt;=1 and "advcl:if" in [x["deprel"] for x in node.deps]' | less -R</pre>
    <pre>( udapy -T read.Conllu files="`echo UD_Czech-{PUD,PDT,FicTree,CAC,CLTT}/*.conllu`" util.Filter mark=1 keep_tree_if_node='len(node.deps)&gt;=1 and "advcl:aby" in [x["deprel"] for x in nodeeps]' | less -R ) 2&gt;/dev/null</pre></p-->
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints edeprels of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_edeprels
{
    my $data = shift;
    my $languages = shift; # ref to hash read from YAML, indexed by names
    my $functions = shift; # ref to global array
    # Print the data on the web page.
    print("  <h2>Permitted case enhancements for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    print("  <table>\n");
    my $i = 0;
    foreach my $lcode (@lcodes)
    {
        # Get the number of edeprels permitted in this language.
        my @edeprels = sort(keys(%{$data->{$lcode}}));
        my $n = scalar(@edeprels);
        next if($n==0);
        # Repeat the headers every 20 rows.
        if($i % 20 == 0)
        {
            print("    <tr><th colspan=2>Language</th><th>Total</th>");
            my $j = 0;
            foreach my $f (@{$functions})
            {
                next if(!defined($f->[2]));
                # Repeat the language every 12 columns... but not in the header line.
                if($j != 0 && $j % 12 == 0)
                {
                    print('<th></th>');
                }
                $j++;
                print("<th>$f->[2]</th>");
            }
            print("</tr>\n");
        }
        $i++;
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
        my $j = 0;
        foreach my $f (@{$functions})
        {
            next if(!defined($f->[2]));
            # Repeat the language every 12 columns.
            if($j != 0 && $j % 12 == 0)
            {
                print("<td><b>$lcode</b></td>");
            }
            $j++;
            print('<td>');
            print(join(' ', grep {my $x = $_; scalar(grep {$_->{function} eq $f->[2]} (@{$data->{$lcode}{$x}{functions}})) > 0} (@edeprels)));
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
    my $functions = shift; # ref to array of pairs (arrays)
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
    # Edeprel is the name of the edeprel whose details we want to see and edit.
    $config{edeprel} = decode('utf8', $query->param('edeprel'));
    if(!defined($config{edeprel}) || $config{edeprel} =~ m/^\s*$/)
    {
        $config{edeprel} = '';
    }
    # Forms of edeprels are prescribed in the UD guidelines.
    elsif($config{edeprel} =~ m/^([\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*(:[a-z]+)?|[a-z]+)$/)
    {
        $config{edeprel} = $1;
    }
    else
    {
        push(@errors, "Edeprel '$config{edeprel}' does not have the form prescribed by the guidelines");
    }
    #--------------------------------------------------------------------------
    # Origedeprel is the original name of the edeprel we were editing (we may
    # have changed it in edeprel).
    $config{origedeprel} = decode('utf8', $query->param('origedeprel'));
    if(!defined($config{origedeprel}) || $config{origedeprel} =~ m/^\s*$/)
    {
        $config{origedeprel} = '';
    }
    # Forms of edeprels are prescribed in the UD guidelines.
    elsif($config{origedeprel} =~ m/^([\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*(:[a-z]+)?|[a-z]+)$/)
    {
        $config{origedeprel} = $1;
    }
    else
    {
        push(@errors, "Orig edeprel '$config{origedeprel}' does not have the form prescribed by the guidelines");
    }
    #--------------------------------------------------------------------------
    # Lex is the lexical case marker in the edeprel.
    $config{lex} = decode('utf8', $query->param('lex'));
    if(!defined($config{lex}) || $config{lex} =~ m/^\s*$/)
    {
        $config{lex} = '';
    }
    # Form of lex is prescribed in the UD guidelines.
    elsif($config{lex} =~ m/^([\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)$/)
    {
        $config{lex} = $1;
    }
    else
    {
        push(@errors, "Lexical marker '$config{lex}' does not have the form prescribed by the guidelines");
    }
    #--------------------------------------------------------------------------
    # Morph is the morphological case marker in the edeprel.
    $config{morph} = decode('utf8', $query->param('morph'));
    if(!defined($config{morph}) || $config{morph} =~ m/^\s*$/)
    {
        $config{morph} = '';
    }
    # Form of morph is prescribed in the UD guidelines.
    elsif($config{morph} =~ m/^([a-z]+)$/)
    {
        $config{morph} = $1;
    }
    else
    {
        push(@errors, "Morphological marker '$config{morph}' does not have the form prescribed by the guidelines");
    }
    #--------------------------------------------------------------------------
    # What universal relations does this edeprel extend?
    foreach my $deprel (qw(obl nmod advcl acl conj))
    {
        my $extdeprel = 'ext'.$deprel;
        $config{$extdeprel} = decode('utf8', $query->param($extdeprel));
        if(!defined($config{$extdeprel}) || $config{$extdeprel} =~ m/^\s*$/)
        {
            $config{$extdeprel} = '';
        }
        else
        {
            $config{$extdeprel} = 1;
        }
    }
    #--------------------------------------------------------------------------
    # There may be multiple functions and each will have its own set of numbered attributes.
    foreach my $f (@{$functions})
    {
        if(defined($f->[2]))
        {
            my $func = 'func'.$f->[2];
            $config{$func} = decode('utf8', $query->param($func));
            if(!defined($config{$func}) || $config{$func} =~ m/^\s*$/)
            {
                $config{$func} = '';
            }
            else
            {
                $config{$func} = 1;
            }
            #--------------------------------------------------------------------------
            # Example in the original language may contain letters (including Unicode
            # letters), spaces, punctuation (including Unicode punctuation). Square
            # brackets have a special meaning, they mark the word we focus on. We
            # probably do not need < > & "" and we could ban them for safety (but
            # it is not necessary if we make sure to always escape them when inserting
            # them in HTML we generate). We may need the apostrophe in some languages,
            # though.
            my $ename = "example$f->[2]";
            $config{$ename} = decode('utf8', $query->param($ename));
            if(!defined($config{$ename}) || $config{$ename} =~ m/^\s*$/)
            {
                $config{$ename} = '';
            }
            else
            {
                # Remove duplicate, leading and trailing spaces.
                $config{$ename} =~ s/^\s+//;
                $config{$ename} =~ s/\s+$//;
                $config{$ename} =~ s/\s+/ /sg;
                if($config{$ename} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
                {
                    push(@errors, "Example '$config{$ename}' contains characters other than letters, numbers, punctuation and space");
                }
                elsif($config{$ename} =~ m/[<>&"]/) # "
                {
                    push(@errors, "Example '$config{$ename}' contains less-than, greater-than, ampersand or the ASCII quote");
                }
                # All characters that are allowed in a lemma must be allowed inside the square brackets.
                # In addition, we now also allow the ZERO WIDTH JOINER.
                elsif($config{$ename} !~ m/\[.+\]/) #'
                {
                    push(@errors, "Example '$config{$ename}' does not contain a sequence of characters enclosed in [square brackets]");
                }
                if($config{$ename} =~ m/^(.+)$/)
                {
                    $config{$ename} = $1;
                }
            }
            #--------------------------------------------------------------------------
            # English translation of the example is provided if the current language is
            # not English. We can probably allow the same regular expressions as for
            # the original example, although we typically do not need non-English
            # letters in the English translation.
            $ename = "exampleen$f->[2]";
            $config{$ename} = decode('utf8', $query->param($ename));
            if(!defined($config{$ename}) || $config{$ename} =~ m/^\s*$/)
            {
                $config{$ename} = '';
            }
            else
            {
                # Remove duplicate, leading and trailing spaces.
                $config{$ename} =~ s/^\s+//;
                $config{$ename} =~ s/\s+$//;
                $config{$ename} =~ s/\s+/ /sg;
                if($config{$ename} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
                {
                    push(@errors, "Example translation '$config{$ename}' contains characters other than letters, numbers, punctuation and space");
                }
                elsif($config{$ename} =~ m/[<>&"]/) # "
                {
                    push(@errors, "Example translation '$config{$ename}' contains less-than, greater-than, ampersand or the ASCII quote");
                }
                if($config{$ename} =~ m/^(.+)$/)
                {
                    $config{$ename} = $1;
                }
            }
            #--------------------------------------------------------------------------
            # Comment is an optional English text. Since it may contain a word from the
            # language being documented, we should allow everything that is allowed in
            # the example.
            my $cname = "comment$f->[2]";
            $config{$cname} = decode('utf8', $query->param($cname));
            if(!defined($config{$cname}) || $config{$cname} =~ m/^\s*$/)
            {
                $config{$cname} = '';
            }
            else
            {
                # Remove duplicate, leading and trailing spaces.
                $config{$cname} =~ s/^\s+//;
                $config{$cname} =~ s/\s+$//;
                $config{$cname} =~ s/\s+/ /sg;
                if($config{$cname} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
                {
                    push(@errors, "Comment '$config{$cname}' contains characters other than letters, numbers, punctuation and space");
                }
                elsif($config{$cname} =~ m/[<>&"]/) # "
                {
                    push(@errors, "Comment '$config{$cname}' contains less-than, greater-than, ampersand or the ASCII quote");
                }
                if($config{$cname} =~ m/^(.+)$/)
                {
                    $config{$cname} = $1;
                }
            }
        }
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
    # a new edeprel.
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
# Reads the data about edeprels in each language (edeprels.json). Returns a
# reference to the hash.
#------------------------------------------------------------------------------
sub read_edeprels_json
{
    my $path = shift; # docs-automation/valrules
    my $data = json_file_to_perl("$path/edeprels.json")->{edeprels};
    return $data;
}



#------------------------------------------------------------------------------
# Dumps the edeprel data as a JSON file.
#------------------------------------------------------------------------------
sub write_edeprels_json
{
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl instead.",'."\n\n";
    $json .= '"edeprels": {'."\n";
    my @ljsons = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my $ljson = '"'.$lcode.'"'.": {\n";
        my @ejsons = ();
        my @edeprels = sort(keys(%{$data->{$lcode}}));
        foreach my $e (@edeprels)
        {
            my $ejson = '"'.valdata::escape_json_string($e).'": ';
            my @extends = sort(@{$data->{$lcode}{$e}{extends}});
            # Sort the existing functions following the global list of known functions.
            my %sortval;
            for(my $i = 0; $i <= $#functions; $i++)
            {
                $sortval{$functions[$i][2]} = $i;
            }
            my @efunctions = sort {$sortval{$a->{function}} <=> $sortval{$b->{function}}} (@{$data->{$lcode}{$e}{functions}});
            my @frecords;
            foreach my $function (@efunctions)
            {
                my @frecord =
                (
                    ['function'  => $function->{function}],
                    ['example'   => $function->{example}],
                    ['exampleen' => $function->{exampleen}],
                    ['comment'   => $function->{comment}]
                );
                push(@frecords, \@frecord);
            }
            my @record =
            (
                ['lex'         => $data->{$lcode}{$e}{lex}],
                ['morph'       => $data->{$lcode}{$e}{morph}],
                ['extends'     => \@extends, 'list'],
                ['functions'   => \@frecords, 'list of structures'],
                ['lastchanged' => $data->{$lcode}{$e}{lastchanged}],
                ['lastchanger' => $data->{$lcode}{$e}{lastchanger}]
            );
            $ejson .= valdata::encode_json(@record);
            push(@ejsons, $ejson);
        }
        $ljson .= join(",\n", @ejsons)."\n";
        $ljson .= '}';
        push(@ljsons, $ljson);
    }
    $json .= join(",\n", @ljsons)."\n";
    $json .= "}}\n";
    open(JSON, ">$filename") or confess("Cannot write '$filename': $!");
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
