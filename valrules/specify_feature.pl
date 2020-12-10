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
my @functions =
(
    ['Copula (tagged AUX)', 'cop.AUX'],
    ['Copula (tagged PRON/DET)', 'cop.PRON'],
    ['Periphrastic aspect: perfect', 'Aspect=Perf'],
    ['Periphrastic aspect: progressive', 'Aspect=Prog'],
    ['Periphrastic aspect: iterative', 'Aspect=Iter'],
    ['Periphrastic tense: past', 'Tense=Past'],
    ['Periphrastic tense: present', 'Tense=Pres'],
    ['Periphrastic tense: future', 'Tense=Fut'],
    ['Periphrastic voice: passive', 'Voice=Pass'],
    ['Periphrastic voice: causative', 'Voice=Cau'],
    ['Periphrastic mood: conditional', 'Mood=Cnd'],
    ['Periphrastic mood: imperative', 'Mood=Imp'],
    ['Needed in negative clauses (like English “do”, not like “not”)', 'neg'],
    ['Needed in interrogative clauses (like English “do”)', 'int'],
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
  <title>Specify features in UD</title>
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
    print("  <h1>Specify features for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_feature.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit features of that language.
else
{
    # Read the data file from JSON.
    my $data = valdata::read_feats_json($path);
    my %data = %{$data};
    foreach my $lcode (keys(%data))
    {
        if(!exists($lname_by_code{$lcode}))
        {
            confess("Unknown language code '$lcode' in the JSON file");
        }
    }
    # Perform an action according to the CGI parameters.
    # Saving may be needed even for documenting undocumented auxiliaries.
    if($config{save})
    {
        process_form_data(\%data);
    }
    # If we are not saving but have received a feature, it means the feature should be edited.
    elsif($config{feature} ne '')
    {
        summarize_guidelines();
        print_feature_details(\%data);
        print_feature_form(\%data);
        print_values_in_all_languages(\%data);
    }
    else
    {
        summarize_guidelines();
        print_features_for_language(\%data);
        # Show all known auxiliaries so the user can compare. This and related languages first.
        print_all_features(\%data);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of features and values permitted in the current language.
#------------------------------------------------------------------------------
sub print_features_for_language
{
    my $data = shift;
    if(exists($data->{$config{lcode}}))
    {
        my $ldata = $data->{$config{lcode}};
        my @features = sort(keys(%{$ldata}));
        print("  <h2>Features</h2>\n");
        print("  <p><b>Currently permitted:</b> ".join(', ', map {"<a href=\"specify_feature.pl?lcode=$config{lcode}&amp;feature=$_\">$_</a>"} (grep {$ldata->{$_}{permitted}} (@features)))."</p>\n");
        my @afeatures = ();
        foreach my $f (@features)
        {
            if(!defined($ldata->{$f}{unused_uvalues}))
            {
                die("Undefined unused_uvalues for feature '$f'");
            }
            if(!defined($ldata->{$f}{unused_lvalues}))
            {
                die("Undefined unused_lvalues for feature '$f'");
            }
            my $nuu = scalar(@{$ldata->{$f}{unused_uvalues}});
            my $nul = scalar(@{$ldata->{$f}{unused_lvalues}});
            if(!$ldata->{$f}{permitted} && $nuu + $nul > 0)
            {
                push(@afeatures, $f);
            }
        }
        print("  <p><b>Currently unused universal features:</b> ".join(', ', map {"<a href=\"specify_feature.pl?lcode=$config{lcode}&amp;feature=$_\">$_</a>"} (grep {$ldata->{$_}{type} eq 'universal'} (@afeatures)))."</p>\n");
        print("  <p><b>Other features that can be permitted:</b> ".join(', ', map {"<a href=\"specify_feature.pl?lcode=$config{lcode}&amp;feature=$_\">$_</a>"} (grep {$ldata->{$_}{type} eq 'lspec'} (@afeatures)))."</p>\n");
        my @undocumented = grep {$ldata->{$_}{doc} !~ m/^(global|local)$/} (@features);
        if(scalar(@undocumented) > 0)
        {
            print("  <p><b>Undocumented features cannot be used:</b> ".join(', ', @undocumented)."</p>\n");
        }
        my @errors = ();
        foreach my $f (@features)
        {
            my $howdoc = $ldata->{$f}{doc} =~ m/^(global|gerror)$/ ? 'global' : $ldata->{$f}{doc} =~ m/^(local|lerror)$/ ? 'local' : 'none';
            my $href;
            my $file = $f;
            $file =~ s/\[([a-z]+)\]/-$1/;
            if($howdoc eq 'global')
            {
                $href = "https://universaldependencies.org/u/feat/$file.html";
            }
            elsif($howdoc eq 'local')
            {
                $href = "https://universaldependencies.org/$config{lcode}/feat/$file.html";
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
        # Warn about feature values that were declared for the language in tools/data but they are not documented.
        my @fvs = ();
        foreach my $f (@features)
        {
            # Do not look at 'permitted' now. The feature may be permitted but
            # there might still be values that are not permitted.
            if(defined($ldata->{$f}{evalues}))
            {
                my @values = sort(@{$ldata->{$f}{evalues}});
                foreach my $v (@values)
                {
                    push(@fvs, "$f=$v");
                }
            }
        }
        if(scalar(@fvs) > 0)
        {
            print("  <h2>Feature values previously declared but undocumented</h2>\n");
            print("  <p>".join(' ', @fvs)."</p>\n");
        }
    }
    else
    {
        die("No information about features for language '$config{lcode}'");
    }
}



#------------------------------------------------------------------------------
# Prints the list of values permitted for a given feature in a given language.
#------------------------------------------------------------------------------
sub print_feature_details
{
    my $data = shift;
    if(exists($data->{$config{lcode}}))
    {
        print("  <h2>$config{feature}</h2>\n");
        if(exists($data->{$config{lcode}}{$config{feature}}))
        {
            my $fdata = $data->{$config{lcode}}{$config{feature}};
            my $type = $fdata->{type};
            $type = 'language-specific' if($type eq 'lspec');
            my $howdoc = $fdata->{doc} =~ m/^(global|gerror)$/ ? 'global' : $fdata->{doc} =~ m/^(local|lerror)$/ ? 'local' : 'none';
            my $href;
            my $file = $config{feature};
            $file =~ s/\[([a-z]+)\]/-$1/;
            if($howdoc eq 'global')
            {
                $href = "https://universaldependencies.org/u/feat/$file.html";
            }
            elsif($howdoc eq 'local')
            {
                $href = "https://universaldependencies.org/$config{lcode}/feat/$file.html";
            }
            if($fdata->{permitted})
            {
                my $howdocly = $howdoc.'ly';
                print("  <p>This $type feature is currently permitted in $lname_by_code{$config{lcode}} ".
                           "and is $howdocly documented <a href=\"$href\">here</a>.</p>\n");
            }
            else
            {
                print("  <p>This $type feature is currently not permitted in $lname_by_code{$config{lcode}}.");
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
                    for my $e (@{$fdata->{error}})
                    {
                        print("    <li style='color:red'>$e</li>\n");
                    }
                    print("  </ul>\n");
                }
            }
        }
        else
        {
            die("No information about feature '$config{feature}' in language '$config{lcode}'");
        }
    }
    else
    {
        die("No information about features for language '$config{lcode}'");
    }
}



#------------------------------------------------------------------------------
# Prints the form where a particular feature can be edited.
#------------------------------------------------------------------------------
sub print_feature_form
{
    my $data = shift;
    if($config{feature} eq '')
    {
        die("Unknown feature");
    }
    if(!exists($data->{$config{lcode}}{$config{feature}}))
    {
        die("Feature '$config{feature}' not found in language '$config{lcode}'");
    }
    my $record = $data->{$config{lcode}}{$config{feature}};
    print("  <h3>Values permitted for individual parts of speech</h3>\n");
    print <<EOF
  <form action="specify_feature.pl" method="post" enctype="multipart/form-data">
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
    print("      <td>Value</td>\n");
    my @upos = qw(ADJ ADP ADV AUX CCONJ DET INTJ NOUN NUM PART PRON PROPN PUNCT SCONJ SYM VERB X);
    foreach my $u (@upos)
    {
        print("      <td>$u</td>\n");
    }
    print("    </tr>\n");
    #--------------------------------------------------------------------------
    # Rows for individual values
    my @used = sort(@{$record->{uvalues}}, @{$record->{lvalues}});
    my @unused = sort(@{$record->{unused_uvalues}}, @{$record->{unused_lvalues}});
    foreach my $v (@used, @unused)
    {
        print("    <tr>\n");
        my $hv = htmlescape($v);
        print("      <td>$hv</td>\n");
        foreach my $u (@upos)
        {
            my $name = "value.$hv.$u";
            my $checked = exists($record->{byupos}{$u}{$v}) ? ' checked' : '';
            print("      <td><input type=\"checkbox\" id=\"$name\" name=\"$name\" value=\"1\"$checked /></td>\n");
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
    my $maxifun = 1;
    for(my $ifun = 1; exists($config{"function$ifun"}) && defined($config{"function$ifun"}) && $config{"function$ifun"} ne ''; $ifun++)
    {
        $maxifun = $ifun;
        my $fname = "function$ifun";
        if($config{$fname} ne '')
        {
            print("    <li>function $ifun = '".htmlescape($config{$fname})."'</li>\n");
            my $uf = $config{$fname};
            $uf =~ s/^cop\..+$/cop/;
            if(exists($unique_functions{$uf}))
            {
                print("    <li style='color:red'>ERROR: Repeated function '$uf'</li>\n");
                $error = 1;
            }
            $unique_functions{$uf}++;
        }
        else
        {
            print("    <li style='color:red'>ERROR: Missing function $ifun</li>\n");
            $error = 1;
        }
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
        valdata::write_feats_json($data, "$path/data.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_feature.pl" method="post" enctype="multipart/form-data">
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
    Specify features for $lname_by_code{$config{lcode}}</h1>
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints features of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_features
{
    my $data = shift;
    # Print the data on the web page.
    print("  <h2>Permitted features for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    # Get the list of all known feature names. Every language has a different set.
    my %features;
    foreach my $lcode (@lcodes)
    {
        my @features = keys(%{$data->{$lcode}});
        foreach my $f (@features)
        {
            $features{$f} = $data->{$lcode}{$f}{type};
        }
    }
    my @features = sort
    {
        # Universal features come before language-specific.
        my $r = $features{$b} cmp $features{$a};
        unless($r)
        {
            $r = $a cmp $b;
        }
        $r
    }
    (keys(%features));
    print("  <table>\n");
    my $i = 0;
    foreach my $lcode (@lcodes)
    {
        # Repeat the headers every 20 rows.
        if($i % 20 == 0)
        {
            print("    <tr><th colspan=2>Language</th><th>Total</th>");
            my $j = 0;
            foreach my $f (@features)
            {
                # Repeat the language every 12 columns.
                if($j != 0 && $j % 12 == 0)
                {
                    print('<th></th>');
                }
                $j++;
                print("<th>$f</th>");
            }
            print("</tr>\n");
        }
        $i++;
        # Get the number of features permitted in this language.
        my $n = scalar(grep {exists($data->{$lcode}{$_}) && $data->{$lcode}{$_}{permitted}} (@features));
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
        my $j = 0;
        foreach my $f (@features)
        {
            # Repeat the language every 12 columns.
            if($j != 0 && $j % 12 == 0)
            {
                print("<td>$lcode</td>");
            }
            $j++;
            print('<td>');
            if(exists($data->{$lcode}{$f}) && $data->{$lcode}{$f}{permitted})
            {
                my $nu = scalar(@{$data->{$lcode}{$f}{uvalues}});
                my $nl = scalar(@{$data->{$lcode}{$f}{lvalues}});
                if($nu + $nl > 0)
                {
                    print($nu);
                    if($nl > 0)
                    {
                        print("+$nl");
                    }
                }
            }
            print('</td>');
        }
        print("</tr>\n");
    }
    print("  </table>\n");
}



#------------------------------------------------------------------------------
# Prints values of one feature by UPOS of all languages, this and related
# languages first.
#------------------------------------------------------------------------------
sub print_values_in_all_languages
{
    my $data = shift;
    # Print the data on the web page.
    print("  <h2>Permitted values for this and other languages</h2>\n");
    my @lcodes = langgraph::sort_lcodes_by_relatedness($languages, $config{lcode});
    my @upos = qw(ADJ ADP ADV AUX CCONJ DET INTJ NOUN NUM PART PRON PROPN PUNCT SCONJ SYM VERB X);
    print("  <table>\n");
    my $i = 0;
    foreach my $lcode (@lcodes)
    {
        if(exists($data->{$lcode}{$config{feature}}))
        {
            # Repeat the headers every 20 rows.
            if($i % 20 == 0)
            {
                print("    <tr><th colspan=2>Language</th><th>Total</th>");
                foreach my $u (@upos)
                {
                    print("<th>$u</th>");
                }
                print("</tr>\n");
            }
            $i++;
            my $fdata = $data->{$lcode}{$config{feature}};
            # Get the number of values permitted in this language.
            my $n = scalar(@{$fdata->{uvalues}}) + scalar(@{$fdata->{lvalues}});
            print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
            foreach my $u (@upos)
            {
                print('<td>');
                if(exists($fdata->{byupos}{$u}))
                {
                    #print(join(' ', sort(keys(%{$fdata->{byupos}{$u}}))));
                    ###!!! At present the 'byupos' hash may include values that are not permitted!
                    ###!!! The hash has been collected from treebank data and has not been pruned yet.
                    ###!!! We thus must prune it here.
                    my @values = sort(grep {exists($fdata->{byupos}{$u}{$_})} (@{$fdata->{uvalues}}, @{$fdata->{lvalues}}));
                    print(join(' ', @values));
                }
                print('</td>');
            }
            print("</tr>\n");
        }
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
    # Feature is the name of the feature whose details we want to see and edit.
    $config{feature} = decode('utf8', $query->param('feature'));
    if(!defined($config{feature}) || $config{feature} =~ m/^\s*$/)
    {
        $config{feature} = '';
    }
    # Forms of feature names are prescribed in the UD guidelines.
    elsif($config{feature} =~ m/^([A-Z][A-Za-z0-9]*(\[[a-z]+\])?)$/)
    {
        $config{feature} = $1;
    }
    else
    {
        push(@errors, "Feature '$config{feature}' does not have the form prescribed by the guidelines");
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
