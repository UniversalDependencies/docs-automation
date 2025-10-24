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
use common;
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
my @functions =
(
    ['Copula (tagged AUX)', 'cop.AUX'],
    ['Copula (tagged PRON/DET)', 'cop.PRON'],
    ['Periphrastic aspect: perfect', 'Aspect=Perf'],
    ['Periphrastic aspect: imperfect', 'Aspect=Imp'],
    ['Periphrastic aspect: habitual', 'Aspect=Hab'],
    ['Periphrastic aspect: durative', 'Aspect=Dur'],
    ['Periphrastic aspect: progressive', 'Aspect=Prog'],
    ['Periphrastic aspect: prospective', 'Aspect=Prosp'],
    # Inchoative aspect marks beginning of a state or action. It should not be
    # routinely used for verbs like "start" and "begin" unless their equivalents
    # pass language-specific tests for auxiliary verbs. This is the case e.g. in
    # Nahuatl, but the English construction "to start to do something" should be
    # annotated using "xcomp".
    ['Periphrastic aspect: inchoative', 'Aspect=Inch'],
    ['Periphrastic aspect: iterative', 'Aspect=Iter'],
    # Momentane aspect is a term from the Finnish grammar (https://en.wikipedia.org/wiki/Momentane)
    # but we need it because of Nahuatl (mail from Robert Pugh 2023-10-09). It
    # follows the verb X (like other auxiliaries in Nahuatl) and adds the meaning
    # "to suddenly/quickly do X".
    ['Periphrastic aspect: momentane', 'Aspect=Mmnt'],
    ['Periphrastic tense: past', 'Tense=Past'],
    ['Periphrastic tense: present', 'Tense=Pres'],
    ['Periphrastic tense: future', 'Tense=Fut'],
    ['Periphrastic voice: reciprocal', 'Voice=Rcp'],
    ['Periphrastic voice: passive', 'Voice=Pass'],
    ['Periphrastic voice: causative', 'Voice=Cau'],
    ['Periphrastic mood: conditional', 'Mood=Cnd'],
    ['Periphrastic mood: subjunctive', 'Mood=Sub'],
    ['Periphrastic mood: imperative', 'Mood=Imp'],
    ['Periphrastic mood: jussive', 'Mood=Jus'],
    ['Periphrastic mood: optative', 'Mood=Opt'],
    ['Periphrastic mood: benefactive', 'Mood=Ben'],
    ['Periphrastic mood: irrealis', 'Mood=Irr'],
    ['Cross-reference of core argument(s) without additional TAMVE features', 'agr'],
    ['Needed in negative clauses (like English “do”, not like “not”)', 'neg'],
    ['Needed in interrogative clauses (like English “do”)', 'int'],
    ['Modal auxiliary: necessitative (“must, should”)', 'Mood=Nec'],
    ['Modal auxiliary: potential (“can, might”)', 'Mood=Pot'],
    ['Modal auxiliary: desiderative (“want”)', 'Mood=Des'],
    ['Evidential auxiliary: firsthand', 'Evident=Fh'],
    ['Evidential auxiliary: non-firsthand', 'Evident=Nfh'],
    ['Politeness auxiliary: formal', 'Polite=Form'],
    ['Politeness auxiliary: informal', 'Polite=Infm']
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
print(common::generate_html_start('auxiliaries'));
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
    # Read the data file from JSON.
    my %data = read_data_json();
    # Check whether there are any undocumented auxiliaries. Documenting them
    # has higher priority than any other action the user may want to do.
    my $n_undocumented = 0;
    # It is possible that there are no auxiliaries for my language so far.
    if(exists($data{$config{lcode}}))
    {
        my $auxiliaries = $data{$config{lcode}};
        $n_undocumented = scalar(grep {$auxiliaries->{$_}{status} ne 'documented'} (keys(%{$auxiliaries})));
    }
    # Perform an action according to the CGI parameters.
    # Saving may be needed even for documenting undocumented auxiliaries.
    if($config{save})
    {
        process_form_data(\%data);
    }
    # If we are not saving but have received a lemma, it means the lemma should be edited.
    # This may also be needed for documenting undocumented auxiliaries.
    elsif($config{lemma} ne '')
    {
        summarize_guidelines();
        print_lemma_form(\%data);
        print_all_auxiliaries(\%data, $languages);
    }
    # Now if there are any undocumented auxiliaries, offer documenting them as the only possible action.
    elsif($n_undocumented > 0)
    {
        summarize_guidelines();
        print_undocumented_auxiliaries(\%data);
        print_all_auxiliaries(\%data, $languages);
    }
    elsif($config{add}) # addcop and addnoncop will be used inside print_lemma_form()
    {
        summarize_guidelines();
        print_lemma_form(\%data);
        print_all_auxiliaries(\%data, $languages);
    }
    else
    {
        summarize_guidelines();
        print_edit_add_menu(\%data);
        # Show all known auxiliaries so the user can compare. This and related languages first.
        print_all_auxiliaries(\%data, $languages);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of undocumented auxiliaries.
#------------------------------------------------------------------------------
sub print_undocumented_auxiliaries
{
    my $data = shift;
    my %auxiliaries = %{$data->{$config{lcode}}};
    my @undocumented = sort(grep {$auxiliaries{$_}{status} ne 'documented'} (keys(%auxiliaries)));
    my $n = scalar(@undocumented);
    if($n > 0)
    {
        my $hrefs = get_lemma_links_to_edit(@undocumented);
        # Already documented auxiliaries should stay available for editing while
        # the rest is being documented (e.g. the user may want to return to a
        # copula and explain its deficient paradigm if they find they have forgotten it).
        # The only thing we will hide until all auxiliaries are documented is the Add new button.
        my @documented = sort(grep {$auxiliaries{$_}{status} eq 'documented'} (keys(%auxiliaries)));
        if(scalar(@documented) > 0)
        {
            $hrefs .= ' | Already documented: '.get_lemma_links_to_edit(@documented);
        }
        my $suffix = $n > 1 ? 'ies' : 'y';
        print("  <h2 style='color:red'>You have $n undocumented auxiliar$suffix!</h2>\n");
        print("  <p>Please edit each undocumented auxiliary and supply the missing information.</p>\n");
        print("  <p>$hrefs</p>\n");
    }
}



#------------------------------------------------------------------------------
# Prints the list of documented auxiliaries for editing and the button to add
# a new auxiliary.
#------------------------------------------------------------------------------
sub print_edit_add_menu
{
    my $data = shift;
    print("  <h2>Edit or add auxiliaries</h2>\n");
    my @ndcop = ();
    if(exists($data->{$config{lcode}}))
    {
        my @lemmas = sort(keys(%{$data->{$config{lcode}}}));
        my $hrefs = get_lemma_links_to_edit(@lemmas);
        print("  <p>$hrefs</p>\n");
        # Look for copulas without documented deficient paradigm. If there is
        # one, we will not offer adding another copula.
        foreach my $lemma (@lemmas)
        {
            my @functions = @{$data->{$config{lcode}}{$lemma}{functions}};
            my @ndcop_lemma = grep {$_->{function} =~ m/^cop\./ && $_->{deficient} eq ''} (@functions);
            if(scalar(@ndcop_lemma) > 0)
            {
                push(@ndcop, $lemma);
            }
        }
    }
    print("  <form action=\"specify_auxiliary.pl\" method=\"post\" enctype=\"multipart/form-data\">\n");
    print("    <input name=lcode type=hidden value=\"$config{lcode}\" />\n");
    print("    <input name=ghu type=hidden value=\"$config{ghu}\" />\n");
    if(scalar(@ndcop)==0)
    {
        print("    <input name=add type=submit value=\"Add copula\" />\n");
        print("    <input name=add type=submit value=\"Add other\" />\n");
    }
    else
    {
        print("    The copula has been specified <i>(".join(', ', @ndcop).")</i>.\n");
        print("    <input name=add type=submit value=\"Add non-copula\" />\n");
    }
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Returns a list of lemmas as HTML links to the edit form.
#------------------------------------------------------------------------------
sub get_lemma_links_to_edit
{
    my @lemmas = @_;
    my @hrefs;
    foreach my $lemma0 (@lemmas)
    {
        # For a safe URL we assume that the lemma contains only letters. That should not be a problem normally.
        # We must also allow the hyphen, needed in Skolt Sami "i-ǥõl". (Jack Rueter: It is written with a hyphen. Historically it might be traced to a combination of the AUX:NEG ij and a reduced ǥõl stem derived from what is now the verb õlggâd ʹhave toʹ. The word-initial g has been retained in the fossilized contraction as ǥ, but that same word-initial letter has been lost in the standard verb.)
        # We must also allow the apostrophe, needed in Mbya Guarani "nda'ei" and "nda'ipoi".
        # We must also allow whitespace, needed in Vietnamese "có thể".
        my $lemma = $lemma0;
        $lemma =~ s/[^-\pL\pM' ]//g; #'
        my $alert = '';
        if($lemma ne $lemma0)
        {
            $alert = " <span style='color:red'>ERROR: Lemma must consist only of letters but stripping non-letters from '".htmlescape($lemma0)."' yields '$lemma'!</span>";
        }
        my $urllemma = $lemma;
        $urllemma =~ s/\s+/%20/g;
        my $href = "<a href=\"specify_auxiliary.pl?ghu=$config{ghu}&amp;lcode=$config{lcode}&amp;lemma=$urllemma\">$lemma</a>$alert";
        push(@hrefs, $href);
    }
    return join(' ', @hrefs);
}



#------------------------------------------------------------------------------
# Prints the form where a particular lemma can be edited.
#------------------------------------------------------------------------------
sub print_lemma_form
{
    my $data = shift;
    # This function can be called for an empty lemma, in which case we want to
    # add a new auxiliary. However, if the lemma is non-empty, it must be
    # known.
    my $record;
    if($config{lemma} eq '')
    {
        $record =
        {
            'functions' => [],
            'status'    => 'new'
        };
    }
    elsif(exists($data->{$config{lcode}}{$config{lemma}}))
    {
        $record = $data->{$config{lcode}}{$config{lemma}};
    }
    else
    {
        die("Lemma '$config{lemma}' not found in language '$config{lcode}'");
    }
    # The field Deficient serves to justify multiple copulas per language.
    # It should be available if we are adding or editing a copula or if we are
    # documenting a previously undocumented auxiliary, which could be a copula.
    my $show_deficient = $config{addcop} || $record->{status} eq 'undocumented';
    if(grep {$_->{function} =~ m/^cop\./} (@{$record->{functions}}))
    {
        $show_deficient = 1;
    }
    my $show_exampleen = $config{lcode} ne 'en';
    my $functions_exist = scalar(@{$record->{functions}}) > 0;
    # Sort the existing functions following the global list of known functions.
    # We especially need the copula, if present, to appear first.
    if($functions_exist)
    {
        my %sortval;
        for(my $i = 0; $i <= $#functions; $i++)
        {
            $sortval{$functions[$i][1]} = $i;
        }
        @{$record->{functions}} = sort {$sortval{$a->{function}} <=> $sortval{$b->{function}}} (@{$record->{functions}});
    }
    print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
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
    print("      <td>Lemma</td>\n");
    print("      <td>Function</td>\n");
    print("      <td>Rule</td>\n");
    if($show_deficient)
    {
        print("      <td>Deficient paradigm</td>\n");
    }
    print("      <td>Example</td>\n");
    if($show_exampleen)
    {
        print("      <td>English translation of the example</td>\n");
    }
    print("      <td>Comment</td>\n");
    print("    </tr>\n");
    #--------------------------------------------------------------------------
    # Lemma and the first function
    print("    <tr id=\"inputrow1\">\n");
    print("      <td>");
    if($config{lemma} ne '')
    {
        my $hlemma = htmlescape($config{lemma});
        print("<strong>$hlemma</strong><input name=lemma type=hidden size=10 value=\"$hlemma\" />");
    }
    else
    {
        print("<input name=lemma type=text size=10 />");
    }
    print("</td>\n");
    # If we are adding or editing a copula, the function is restricted.
    if($config{addcop} || $functions_exist && $record->{functions}[0]{function} =~ m/^cop\./)
    {
        print("      <td>\n");
        print("        <select name=function1>\n");
        foreach my $f (@functions)
        {
            next if($f->[1] !~ m/^cop\./);
            my $selected = '';
            if($functions_exist && $f->[1] eq $record->{functions}[0]{function})
            {
                $selected = ' selected';
            }
            print("          <option value=\"$f->[1]\"$selected>".htmlescape($f->[0])."</option>\n");
        }
        print("        </select>\n");
        print("      </td>\n");
        print("      <td>combination of the copula and a nonverbal predicate<input name=rule1 type=hidden value=\"combination of the copula and a nonverbal predicate\" /></td>\n");
    }
    else
    {
        print("      <td>\n");
        print("        <select name=function1>\n");
        print("          <option>-----</option>\n");
        foreach my $f (@functions)
        {
            # The Copula functions should be available if we are documenting an undocumented auxiliary.
            # Otherwise it is not available because we must use 'addcop', see above.
            next if($f->[1] =~ m/^cop\./ && $record->{status} ne 'undocumented');
            my $selected = '';
            if($functions_exist && $f->[1] eq $record->{functions}[0]{function})
            {
                $selected = ' selected';
            }
            print("          <option value=\"$f->[1]\"$selected>".htmlescape($f->[0])."</option>\n");
        }
        print("        </select>\n");
        print("      </td>\n");
        my $hrule = '';
        if($functions_exist)
        {
            $hrule = htmlescape($record->{functions}[0]{rule});
        }
        print("      <td><input name=rule1 type=text size=30 value=\"$hrule\" /></td>\n");
    }
    if($show_deficient)
    {
        my $hdeficient = '';
        if($functions_exist)
        {
            $hdeficient = htmlescape($record->{functions}[0]{deficient});
        }
        print("      <td><input name=deficient1 type=text size=30 value=\"$hdeficient\" /></td>\n");
    }
    my $hexample = '';
    if($functions_exist)
    {
        $hexample = htmlescape($record->{functions}[0]{example});
    }
    print("      <td><input name=example1 type=text size=30 value=\"$hexample\" /></td>\n");
    if($show_exampleen)
    {
        my $hexampleen = '';
        if($functions_exist)
        {
            $hexampleen = htmlescape($record->{functions}[0]{exampleen});
        }
        print("      <td><input name=exampleen1 type=text size=30 value=\"$hexampleen\" /></td>\n");
    }
    my $hcomment = '';
    if($functions_exist)
    {
        $hcomment = htmlescape($record->{functions}[0]{comment});
    }
    print("      <td><input name=comment1 type=text value=\"$hcomment\" /></td>\n");
    print("    </tr>\n");
    #--------------------------------------------------------------------------
    # Additional functions if we already know their values
    for(my $ifun = 2; $ifun <= $#{$record->{functions}} + 1; $ifun++)
    {
        print("    <tr id=\"inputrow$ifun\">\n");
        print("      <td>Function&nbsp;$ifun:</td>\n");
        print("      <td>\n");
        print("        <select name=function$ifun>\n");
        print("          <option>-----</option>\n");
        foreach my $f (@functions)
        {
            # Copula can be the first function but not an additional function.
            next if($f->[1] =~ m/^cop\./);
            my $selected = '';
            if($f->[1] eq $record->{functions}[$ifun-1]{function})
            {
                $selected = ' selected';
            }
            print("          <option value=\"$f->[1]\"$selected>".htmlescape($f->[0])."</option>\n");
        }
        print("        </select>\n");
        print("      </td>\n");
        my $hrule = htmlescape($record->{functions}[$ifun-1]{rule});
        print("      <td><input name=rule$ifun type=text size=30 value=\"$hrule\" /></td>\n");
        if($show_deficient)
        {
            # The additional function cannot be a copula, so we will not provide a field for the deficient paradigm explanation.
            print("      <td></td>\n");
        }
        my $hexample = htmlescape($record->{functions}[$ifun-1]{example});
        print("      <td><input name=example$ifun type=text size=30 value=\"$hexample\" /></td>\n");
        if($show_exampleen)
        {
            my $hexampleen = htmlescape($record->{functions}[$ifun-1]{exampleen});
            print("      <td><input name=exampleen$ifun type=text size=30 value=\"$hexampleen\" /></td>\n");
        }
        my $hcomment = htmlescape($record->{functions}[$ifun-1]{comment});
        print("      <td><input name=comment$ifun type=text value=\"$hcomment\" /></td>\n");
        print("    </tr>\n");
    }
    #--------------------------------------------------------------------------
    # Script to add more functions dynamically if needed
    print <<EOF
    <script type='text/javascript'>
        function addFunction() {
            // Figure out the currently highest number X in tablew row ids ("inputrowX").
            var table = document.getElementById("inputtable");
            var rows = table.rows;
            var n_rows = rows.length;
            var n_functions = n_rows - 2; // without header and footer
            var ifun = n_functions + 1; // number of the new function that we are adding
            //alert("The form currently accepts up to " + n_functions + " functions.");
            var row = table.insertRow(n_rows-1);
            row.id = "inputrow" + ifun
EOF
    ;
    print("            var cell1 = row.insertCell(-1);\n");
    print("            cell1.innerHTML = \"Function&nbsp;\" + ifun + \":\";\n");
    print("            var cell2 = row.insertCell(-1);\n");
    my $html = '';
    # Double-escape newlines and quotes because this HTML is used as a string in JavaScript.
    # Single-escaped quote will break the JavaScript string so that a JavaScript variable can be inserted.
    $html .= "        <select name=function\" + ifun + \">\\n";
    $html .= "          <option>-----</option>\\n";
    foreach my $f (@functions)
    {
        # Copula can be the first function but not an additional function.
        next if($f->[1] =~ m/^cop\./);
        $html .= "          <option value=\\\"$f->[1]\\\">".htmlescape($f->[0])."</option>\\n";
    }
    $html .= "        </select>\\n";
    print("            cell2.innerHTML = \"$html\";\n");
    print("            var cell3 = row.insertCell(-1);\n");
    print("            cell3.innerHTML = \"<input name=rule\" + ifun + \" type=text size=30 />\"\n");
    if($show_deficient)
    {
        # The additional function cannot be a copula, so we will not provide a field for the deficient paradigm explanation.
        print("            var cell4 = row.insertCell(-1);\n");
    }
    print("            var cell5 = row.insertCell(-1);\n");
    print("            cell5.innerHTML = \"<input name=example\" + ifun + \" type=text size=30 />\"\n");
    if($show_exampleen)
    {
        print("            var cell6 = row.insertCell(-1);\n");
        print("            cell6.innerHTML = \"<input name=exampleen\" + ifun + \" type=text size=30 />\"\n");
    }
    print("            var cell7 = row.insertCell(-1);\n");
    print("            cell7.innerHTML = \"<input name=comment\" + ifun + \" type=text />\"\n");
    print("        }\n");
    print("    </script>\n");
    #--------------------------------------------------------------------------
    # Buttons and hints
    print("    <tr id=\"inputfooter\">\n");
    print("      <td><input type=button value=\"More\" title=\"Add fields for another function of this auxiliary\" onclick=\"addFunction()\" /></td>\n");
    # Do not print the hint for the function/rule if the function/rule is fixed (copula).
    # But do print the hint for multiple copulas.
    ###!!! We now print it always because there might be additional, non-copula functions.
    if(0)
    #$config{addcop} || $functions_exist && $record->{functions}[0]{function} =~ m/^cop\./)
    {
        print("      <td></td>\n");
        print("      <td></td>\n");
    }
    else
    {
        print("      <td><small>Missing function that conforms to the guidelines? Contact Dan!</small></td>\n");
        print("      <td><small>E.g. “combination of the auxiliary and a past participle of the main verb”</small></td>\n");
    }
    if($show_deficient)
    {
        print("      <td><small>If you want multiple copulas, you must justify each, e.g. “used in past tense only”</small></td>\n");
    }
    print("      <td><small>Mark the auxiliary by enclosing it in square brackets, e.g., “he [has] done it”</small></td>\n");
    if($show_exampleen)
    {
        print("      <td></td>\n");
    }
    print("      <td></td>\n");
    print("    </tr>\n");
    print("  </table>\n");
    # If we are adding a new lemma, we will have to check that it is really new.
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
# We are processing a Save request after a lemma was edited.
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
    if($config{lemma} ne '')
    {
        print("    <li>lemma = '$config{lemma}'</li>\n");
        if($config{savenew} && exists($data->{$config{lcode}}{$config{lemma}}))
        {
            print("    <li style='color:red'>ERROR: There already is an auxiliary with the lemma '$config{lemma}'. Instead of re-adding it, you should edit it</li>\n");
            $error = 1;
        }
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing lemma</li>\n");
        $error = 1;
    }
    # There may be multiple functions and each will have its own set of numbered attributes.
    my %unique_functions;
    my $copula_among_functions = 0;
    my $deficient = '';
    my $maxifun;
    for(my $ifun = 1; exists($config{"function$ifun"}) && defined($config{"function$ifun"}) && $config{"function$ifun"} ne ''; $ifun++)
    {
        $maxifun = $ifun;
        my $fname = "function$ifun";
        print("    <li>function $ifun = '".htmlescape($config{$fname})."'</li>\n");
        my $uf = $config{$fname};
        $uf =~ s/^cop\..+$/cop/;
        if(exists($unique_functions{$uf}))
        {
            print("    <li style='color:red'>ERROR: Repeated function '$uf'</li>\n");
            $error = 1;
        }
        $unique_functions{$uf}++;
        my $rname = "rule$ifun";
        if($config{$rname} ne '')
        {
            print("    <li>rule $ifun = '".htmlescape($config{$rname})."'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing rule $ifun</li>\n");
            $error = 1;
        }
        # We will assess the obligatoriness of the 'deficient' parameter later.
        my $dname = "deficient$ifun";
        if($config{$dname} ne '')
        {
            print("    <li>deficient $ifun = '".htmlescape($config{$dname})."'</li>\n");
        }
        if($config{$fname} =~ m/^cop\./)
        {
            $copula_among_functions = 1;
            $deficient = $config{$dname};
        }
        my $ename = "example$ifun";
        if($config{$ename} ne '')
        {
            print("    <li>example $ifun = '".htmlescape($config{$ename})."'</li>\n");
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing example $ifun</li>\n");
            $error = 1;
        }
        $ename = "exampleen$ifun";
        if($config{$ename} ne '')
        {
            print("    <li>exampleen $ifun = '".htmlescape($config{$ename})."'</li>\n");
        }
        elsif($config{lcode} ne 'en')
        {
            print("    <li style='color:red'>ERROR: Missing English translation of the example $ifun</li>\n");
            $error = 1;
        }
        my $cname = "comment$ifun";
        if($config{$cname} ne '')
        {
            print("    <li>comment $ifun = '".htmlescape($config{$cname})."'</li>\n");
        }
    } # loop over multiple functions
    if(!defined($maxifun))
    {
        print("    <li style='color:red'>ERROR: Missing function</li>\n");
        $error = 1;
    }
    # Check whether there will be more than one copulas if we add this one to the data.
    # If there will, check that all of them (including the new one) have a distinct
    # explanation of its deficient paradigm.
    if($copula_among_functions)
    {
        my %copjust;
        foreach my $lemma (keys(%{$data->{$config{lcode}}}))
        {
            foreach my $function (@{$data->{$config{lcode}}{$lemma}{functions}})
            {
                if($function->{function} =~ m/^cop\./)
                {
                    $copjust{$lemma} = $function->{deficient};
                    # Even if a lemma has multiple functions, only one of the
                    # functions can be copula, so we do not have to examine the
                    # others.
                    last;
                }
            }
        }
        $copjust{$config{lemma}} = $deficient;
        my $ok = 1;
        my @copulas = sort(keys(%copjust));
        my $n = scalar(@copulas);
        if($n > 1)
        {
            foreach my $lemma (@copulas)
            {
                if($copjust{$lemma} eq '')
                {
                    print("    <li style='color:red'>ERROR: Copula '$lemma' does not have a deficient paradigm, hence there cannot be $n copulas</li>\n");
                    $error = 1;
                }
                if($lemma ne $config{lemma} && $copjust{$lemma} eq $deficient)
                {
                    print("    <li style='color:red'>ERROR: Explanation of deficient paradigm '$deficient' is identical to the explanation given for '$lemma'</li>\n");
                    $error = 1;
                }
            }
        }
    }
    print("  </ul>\n");
    if($error)
    {
        print("  <p style='color:red'><strong>WARNING:</strong> Nothing was saved because there were errors.</p>\n");
    }
    else
    {
        # Create a new record. Even if we are editing an existing auxiliary,
        # all previous values will be thrown away and replaced with the new
        # ones.
        my %record;
        # Do I want to use my local time or universal time in the timestamps?
        #my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = localtime(time());
        my $timestamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 1900+$year, 1+$mon, $mday, $hour, $min, $sec);
        $record{lastchanged} = $timestamp;
        $record{lastchanger} = $config{ghu};
        $record{functions} = [];
        for(my $ifun = 1; $ifun <= $maxifun; $ifun++)
        {
            my %frecord =
            (
                'function'  => $config{"function$ifun"},
                'rule'      => $config{"rule$ifun"},
                'deficient' => $config{"deficient$ifun"},
                'example'   => $config{"example$ifun"},
                'exampleen' => $config{"exampleen$ifun"},
                'comment'   => $config{"comment$ifun"}
            );
            push(@{$record{functions}}, \%frecord);
        }
        $record{status} = 'documented';
        $data->{$config{lcode}}{$config{lemma}} = \%record;
        # Clean up the data. Because of a bug that lived in this script for years, there may be entries without any function specified.
        # Remove such entries from the current language. They will have to be added anew, now including the functions.
        foreach my $lemma (keys(%{$data->{$config{lcode}}}))
        {
            my @frecords = grep {$_->{function} ne ''} (@{$data->{$config{lcode}}{$lemma}{functions}});
            if(scalar(@frecords) > 0)
            {
                $data->{$config{lcode}}{$lemma}{functions} = \@frecords;
            }
            else
            {
                delete($data->{$config{lcode}}{$lemma});
            }
        }
        write_data_json($data, "$path/data.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
    <input name=lcode type=hidden value="$config{lcode}" />
    <input name=ghu type=hidden value="$config{ghu}" />
    <input name=gotolang type=submit value="Return to list" />
  </form>
EOF
        ;
    }
}



#------------------------------------------------------------------------------
# Prints the initial warning that not everything is an auxiliary.
#------------------------------------------------------------------------------
sub summarize_guidelines
{
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
    relation instead. Existential “to be” can be copula only if it is the same
    verb as in equivalence (“John is a teacher”). If the language uses two different
    verbs, then <strong>the existential one is not a copula.</strong>
    A copula is normally tagged <a href="https://universaldependencies.org/u/pos/AUX_.html">AUX</a>.
    Exception: in some languages a personal or demonstrative pronoun /
    determiner can be used as a copula and then we keep it tagged
    <a href="https://universaldependencies.org/u/pos/PRON.html">PRON</a> or
    <a href="https://universaldependencies.org/u/pos/DET.html">DET</a>.</p>
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints auxiliaries of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_auxiliaries
{
    my $data = shift;
    my $languages = shift; # ref to hash read from YAML, indexed by names
    # Print the data on the web page.
    print("  <h2>Known auxiliaries for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    print("  <table>\n");
    print("    <tr><th colspan=2>Language</th><th>Total</th><th>Copula</th><th>Perfect</th><th>Past</th><th>Future</th><th>Passive</th><th>Conditional</th><th>Necessitative</th><th>Potential</th><th>Desiderative</th><th>Other</th><th>Undocumented</th></tr>\n");
    foreach my $lcode (@lcodes)
    {
        my $ldata = $data->{$lcode};
        my @lemmas = sort(keys(%{$ldata}));
        my $n = scalar(@lemmas);
        # Collect lemmas that shall appear in individual columns. Some lemmas
        # may appear in multiple columns.
        my %copula;
        my %perfect;
        my %past;
        my %future;
        my %passive;
        my %conditional;
        my %necessitative;
        my %potential;
        my %desiderative;
        my %other;
        my %undocumented;
        foreach my $lemma (@lemmas)
        {
            if($ldata->{$lemma}{status} eq 'documented')
            {
                foreach my $function (@{$ldata->{$lemma}{functions}})
                {
                    if($function->{function} =~ m/^cop\./)
                    {
                        $copula{$lemma}++;
                    }
                    elsif($function->{function} eq 'Aspect=Perf')
                    {
                        $perfect{$lemma}++;
                    }
                    elsif($function->{function} eq 'Tense=Past')
                    {
                        $past{$lemma}++;
                    }
                    elsif($function->{function} eq 'Tense=Fut')
                    {
                        $future{$lemma}++;
                    }
                    elsif($function->{function} eq 'Voice=Pass')
                    {
                        $passive{$lemma}++;
                    }
                    elsif($function->{function} eq 'Mood=Cnd')
                    {
                        $conditional{$lemma}++;
                    }
                    elsif($function->{function} eq 'Mood=Nec')
                    {
                        $necessitative{$lemma}++;
                    }
                    elsif($function->{function} eq 'Mood=Pot')
                    {
                        $potential{$lemma}++;
                    }
                    elsif($function->{function} eq 'Mood=Des')
                    {
                        $desiderative{$lemma}++;
                    }
                    else
                    {
                        $other{$lemma}++;
                    }
                }
            }
            else
            {
                $undocumented{$lemma}++;
            }
        }
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
        print("<td>".join(' ', sort(keys(%copula)))."</td>");
        print("<td>".join(' ', sort(keys(%perfect)))."</td>");
        print("<td>".join(' ', sort(keys(%past)))."</td>");
        print("<td>".join(' ', sort(keys(%future)))."</td>");
        print("<td>".join(' ', sort(keys(%passive)))."</td>");
        print("<td>".join(' ', sort(keys(%conditional)))."</td>");
        print("<td>".join(' ', sort(keys(%necessitative)))."</td>");
        print("<td>".join(' ', sort(keys(%potential)))."</td>");
        print("<td>".join(' ', sort(keys(%desiderative)))."</td>");
        print("<td>".join(' ', sort(keys(%other)))."</td>");
        print("<td>".join(' ', sort(keys(%undocumented)))."</td></tr>\n");
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
    # Lemma identifies the auxiliary that we are editing or going to edit.
    $config{lemma} = decode('utf8', $query->param('lemma'));
    if(!defined($config{lemma}) || $config{lemma} =~ m/^\s*$/)
    {
        $config{lemma} = '';
    }
    # Lemma can contain letters (L) and marks (M).
    # An example of a mark: U+94D DEVANAGARI SIGN VIRAMA.
    # We must also allow the hyphen, needed in Skolt Sami "i-ǥõl". (Jack Rueter: It is written with a hyphen. Historically it might be traced to a combination of the AUX:NEG ij and a reduced ǥõl stem derived from what is now the verb õlggâd ʹhave toʹ. The word-initial g has been retained in the fossilized contraction as ǥ, but that same word-initial letter has been lost in the standard verb.)
    # We must also allow the apostrophe, needed in Mbya Guarani "nda'ei" and "nda'ipoi".
    # We must also allow whitespace, needed in Vietnamese "có thể".
    elsif($config{lemma} =~ m/^\s*([\pL\pM]+([-' ][\pL\pM]+)?)\s*$/) #'
    {
        $config{lemma} = $1;
    }
    else
    {
        push(@errors, "Lemma '$config{lemma}' contains non-letter characters");
    }
    # There may be multiple functions and each will have its own set of numbered attributes.
    for(my $ifun = 1; ; $ifun++)
    {
        #--------------------------------------------------------------------------
        # Function is a descriptive text (e.g. "Periphrastic aspect: perfect")
        # taken from a pre-defined list of options.
        my $fname = "function$ifun";
        $config{$fname} = decode('utf8', $query->param($fname));
        if(!defined($config{$fname}) || $config{$fname} =~ m/^\s*-*\s*$/)
        {
            $config{$fname} = '';
            # If there is no function, we will store empty values for function 1.
            # If a function with rank higher than 1 is missing, we will not store
            # the empty values and we will not check for any further functions.
            last if($ifun > 1);
        }
        else
        {
            if($config{$fname} =~ m/^(.+)$/)
            {
                $config{$fname} = $1;
            }
            # Verify that the function is one of the functions we defined.
            my @found = grep {$_->[1] eq $config{$fname}} (@{$functions});
            my $n = scalar(@found);
            if($n > 0)
            {
                if($n > 1)
                {
                    print STDERR ("Something is wrong. Multiple functions listed in the source code equal to '$config{$fname}'.\n");
                }
            }
            else
            {
                push(@errors, "Unrecognized function '$config{$fname}'");
            }
        }
        #--------------------------------------------------------------------------
        # Rule is a descriptive text (e.g. "combination of the auxiliary with
        # a participle of the main verb"). It is not restricted to a pre-defined
        # set of options but it should not need more than English letters, spaces,
        # and some basic punctuation.
        my $rname = "rule$ifun";
        $config{$rname} = decode('utf8', $query->param($rname));
        if(!defined($config{$rname}) || $config{$rname} =~ m/^\s*$/)
        {
            $config{$rname} = '';
        }
        elsif($config{$rname} =~ m/^([-A-Za-z \.:\(,;\)]+)$/)
        {
            $config{$rname} = $1;
        }
        else
        {
            push(@errors, "Rule '$config{$rname}' contains characters other than English letters, space, period, comma, semicolon, colon, hyphen, and round brackets");
        }
        #--------------------------------------------------------------------------
        # Deficient [paradigm] is a descriptive text that justifies a copula if
        # there are multiple lemmas of copula in one language.
        my $dname = "deficient$ifun";
        $config{$dname} = decode('utf8', $query->param($dname));
        if(!defined($config{$dname}) || $config{$dname} =~ m/^\s*$/)
        {
            $config{$dname} = '';
        }
        elsif($config{$dname} !~ m/\pL{3}/)
        {
            push(@errors, "Explanation of deficient copula paradigm '$config{$dname}' contains too few letters.");
        }
        elsif($config{$dname} =~ m/^([-A-Za-z \.:\(,;\)]+)$/)
        {
            $config{$dname} = $1;
        }
        else
        {
            push(@errors, "Explanation of deficient copula paradigm '$config{$dname}' contains characters other than English letters, space, period, comma, semicolon, colon, hyphen, and round brackets");
        }
        #--------------------------------------------------------------------------
        # Example in the original language may contain letters (including Unicode
        # letters), spaces, punctuation (including Unicode punctuation). Square
        # brackets have a special meaning, they mark the word we focus on. We
        # probably do not need < > & "" and we could ban them for safety (but
        # it is not necessary if we make sure to always escape them when inserting
        # them in HTML we generate). We may need the apostrophe in some languages,
        # though.
        my $ename = "example$ifun";
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
            if($config{$ename} !~ m/^[\pL\pM$zwj$zwnj\pN\pP ]+$/)
            {
                push(@errors, "Example '$config{$ename}' contains characters other than letters, numbers, punctuation and space");
            }
            elsif($config{$ename} =~ m/[<>&"]/) # "
            {
                push(@errors, "Example '$config{$ename}' contains less-than, greater-than, ampersand or the ASCII quote");
            }
            # All characters that are allowed in a lemma must be allowed inside the square brackets.
            # In addition, we now also allow the ZERO WIDTH JOINER and ZERO WIDTH NON-JOINER.
            elsif($config{$ename} !~ m/\[[\pL\pM$zwj$zwnj]+([-' ][\pL\pM$zwj$zwnj]+)?\]/) #'
            {
                push(@errors, "Example '$config{$ename}' does not contain a sequence of letters enclosed in [square brackets]");
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
        $ename = "exampleen$ifun";
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
            if($config{$ename} !~ m/^[\pL\pM$zwj$zwnj\pN\pP ]+$/)
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
        my $cname = "comment$ifun";
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
            if($config{$cname} !~ m/^[\pL\pM$zwj$zwnj\pN\pP ]+$/)
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
    } # loop over multiple functions
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
    # The parameter 'add' comes from the buttons that launch the form to add
    # a new auxiliary (separate buttons for copula and other auxiliaries).
    $config{add} = decode('utf8', $query->param('add'));
    if(!defined($config{add}))
    {
        $config{add} = 0;
        $config{addcop} = 0;
        $config{addnoncop} = 0;
    }
    elsif($config{add} =~ m/^Add copula$/)
    {
        $config{addcop} = 1;
        $config{add} = 1;
        $config{addnoncop} = 0;
    }
    elsif($config{add} =~ m/^Add (other|non-copula)$/)
    {
        $config{addnoncop} = 1;
        $config{add} = 1;
        $config{addcop} = 0;
    }
    else
    {
        push(@errors, "Unrecognized add button '$config{add}'");
    }
    return %config;
}



#------------------------------------------------------------------------------
# Reads the data about auxiliaries from the JSON file.
#------------------------------------------------------------------------------
sub read_data_json
{
    my %data;
    my $datafile = "$path/data.json";
    my $json = json_file_to_perl($datafile);
    # The $json structure should contain two items, 'WARNING' and 'auxiliaries';
    # the latter should be a reference to an hash of arrays of hashes.
    if(exists($json->{auxiliaries}) && ref($json->{auxiliaries}) eq 'HASH')
    {
        my @lcodes = keys(%{$json->{auxiliaries}});
        foreach my $lcode (@lcodes)
        {
            if(!exists($lname_by_code{$lcode}))
            {
                die("Unknown language code '$lcode' in the JSON file");
            }
            my @lemmas = keys(%{$json->{auxiliaries}{$lcode}});
            foreach my $lemma (@lemmas)
            {
                # We do not have to copy the data item by item to a new record.
                # We can simply copy the reference to the record.
                $data{$lcode}{$lemma} = $json->{auxiliaries}{$lcode}{$lemma};
            }
        }
    }
    else
    {
        die("No auxiliaries found in the JSON file");
    }
    return %data;
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
    $json .= '"auxiliaries": {'."\n";
    my @jsonlanguages = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my $jsonlanguage = '"'.$lcode.'"'.": {\n";
        my @jsonlemmas = ();
        my @lemmas = sort(keys(%{$data->{$lcode}}));
        foreach my $lemma (@lemmas)
        {
            my $jsonlemma = '"'.valdata::escape_json_string($lemma).'": ';
            # Sort the existing functions following the global list of known functions.
            my %sortval;
            for(my $i = 0; $i <= $#functions; $i++)
            {
                $sortval{$functions[$i][1]} = $i;
            }
            my @lemmafunctions = sort {$sortval{$a->{function}} <=> $sortval{$b->{function}}} (@{$data->{$lcode}{$lemma}{functions}});
            my @frecords;
            foreach my $function (@lemmafunctions)
            {
                my @frecord =
                (
                    ['function'  => $function->{function}],
                    ['rule'      => $function->{rule}],
                    ['deficient' => $function->{deficient}],
                    ['example'   => $function->{example}],
                    ['exampleen' => $function->{exampleen}],
                    ['comment'   => $function->{comment}]
                );
                push(@frecords, \@frecord);
            }
            my @record =
            (
                ['functions'   => \@frecords, 'list of structures'],
                ['status'      => $data->{$lcode}{$lemma}{status}],
                ['lastchanged' => $data->{$lcode}{$lemma}{lastchanged}],
                ['lastchanger' => $data->{$lcode}{$lemma}{lastchanger}]
            );
            $jsonlemma .= valdata::encode_json(@record);
            push(@jsonlemmas, $jsonlemma);
        }
        $jsonlanguage .= join(",\n", @jsonlemmas)."\n";
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
