#!/usr/bin/env perl
# Receives notifications from Github about new pushes to UD repositories.
# Copyright © 2018, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use JSON::Parse qw(json_file_to_perl);
# Uvést cestu k Danovým sdíleným knihovnám. Uživatel, pod kterým běží CGI skript, ji nezná.
use lib '/home/zeman/lib';
use dzsys;



# When Github sends the POST request, it probably does not want to see any
# response page. Perhaps it just wants to receive a success response code.
# But the only way I currently know is to generate a regular form response page.
vypsat_html_zacatek();
print("Received.\n"); # This is part of the response sent back to Github.
# Save the data from Github to our log.
open(LOG, ">>log/log.txt");
print LOG ("\n\n\n-------------------------------------------------------------------------------\n");
print LOG (`date`, "\n");
my $k = "\#";
print LOG ("$k ENVIRONMENT\n");
foreach my $klic (sort(keys(%ENV)))
{
    print LOG ("$klic = $ENV{$klic}\n");
}
print LOG ("\n");
print LOG ("$k STDIN\n");
my $json;
while(<>)
{
    $json .= $_;
    print LOG;
}
my $result;
eval { ($result, $json) = jsonparse($json); };
if ($@) {
    print LOG "\n\nOh no! [$@]\n";
}
print LOG ("\n\n");
print LOG ("repository = $result->{repository}{name}\n");
print LOG ("ref = $result->{ref}\n");
print LOG ("commit = $result->{head_commit}{id}\n");
print LOG ("message = $result->{head_commit}{message}\n");
print LOG ("timestamp = $result->{head_commit}{timestamp}\n");
print LOG ("pusher = $result->{pusher}{name}\n");
print LOG ("email = $result->{pusher}{email}\n");
vypsat_html_konec();
if(defined($result))
{
    my $valilog = 'log/validation.log';
    #--------------------------------------------------------------------------
    # UD_Something UD_Something UD_Something UD_Something UD_Something
    #--------------------------------------------------------------------------
    # Change in dev branch of a treebank repository should trigger re-validation of the data.
    # Ignore changes in other branches.
    if($result->{repository}{name} =~ m/^UD_/ && $result->{ref} eq 'refs/heads/dev')
    {
        write_datalog($result);
        system("echo ====================================================================== >>$valilog");
        system("date >>$valilog");
        system("echo Hook on $result->{repository}{name} >>$valilog");
        # Now we must update our copy of that repository and update validation status.
        my $folder = $result->{repository}{name};
        # If this is a new repository, we do not have its clone yet.
        if(-d $folder)
        {
            # The update-validation-report.pl script will call git pull on the $folder.
            # The queue_validate.pl script is a wrapper around update-validation-report.pl,
            # which tries to make sure that two validators do not process the same treebank
            # at the same time.
            system("perl queue_validate.pl $folder >>$valilog 2>&1");
        }
        else
        {
            system("echo This is a new repository. We have to clone it first. >>$valilog");
            system("echo The following command must be run manually because user www-data cannot write to the top folder. >>$valilog");
            system("echo docs-automation/valdan/clone_one.sh $folder >>$valilog");
            #system("docs-automation/valdan/clone_one.sh $folder >>$valilog 2>&1");
        }
    }
    #--------------------------------------------------------------------------
    # tools tools tools tools tools tools tools tools tools tools tools tools
    #--------------------------------------------------------------------------
    # Change in master branch of repository tools may mean changed validation algorithm.
    # Ignore changes in other branches.
    elsif($result->{repository}{name} eq 'tools' && $result->{ref} eq 'refs/heads/master')
    {
        write_datalog($result);
        system("echo ====================================================================== >>$valilog");
        system("date >>$valilog");
        system("echo Hook on $result->{repository}{name} >>$valilog");
        system("(cd tools ; git pull --no-edit ; cd ..) >>$valilog 2>&1");
        # We must figure out what files have changed.
        # Validator data files typically lead to re-validation of one treebank.
        # Validator script leads to re-validation of all treebanks.
        # Other tools are irrelevant.
        my %changed;
        my $revalidate_all = 0;
        my $reevaluate_all = 0;
        foreach my $commit (@{$result->{commits}})
        {
            foreach my $file (@{$commit->{added}}, @{$commit->{modified}})
            {
                if($file =~ m-^(validate\.py|validator/src/validator/.*\.py|check_files\.pl|udlib\.pm)$-)
                {
                    $revalidate_all = 1;
                }
                elsif($file eq 'evaluate_treebank.pl')
                {
                    $reevaluate_all = 1;
                }
                elsif($file =~ m/^data\/(data|feats|deprels|edeprels|tospace)\.json$/ && $commit->{message} =~ m/Updated data specific for ([a-z]{2,3})\./)
                {
                    my $ltcode = $1;
                    $changed{$ltcode}++;
                }
            }
        }
        my @changed = sort(keys(%changed));
        if($revalidate_all)
        {
            print LOG ("changed = validate.py\n");
            # Call the script through the docs-automation repo so that it can find the YAML file with the list of languages.
            system("perl docs-automation/valdan/validate_all.pl >>$valilog 2>&1");
        }
        elsif(scalar(@changed) > 0)
        {
            my $changed = join(' ', @changed);
            system("echo Changed: $changed >>$valilog");
            print LOG ("changed = $changed\n");
            # The validation must be performed in a child process. It may take a long
            # time and the web server will kill this process if we exceed the timeout.
            # Call the script through the docs-automation repo so that it can find the YAML file with the list of languages.
            system("perl docs-automation/valdan/validate_all.pl $changed >>$valilog 2>&1");
        }
        if($reevaluate_all)
        {
            print LOG ("changed = evaluate_treebank.pl\n");
            system("perl evaluate_all.pl | tee evaluation-report.txt >>$valilog 2>&1");
        }
    }
    #--------------------------------------------------------------------------
    # docs docs docs docs docs docs docs docs docs docs docs docs docs docs
    #--------------------------------------------------------------------------
    # Change in pages_source branch of repository docs may mean changes in documentation that are reflected in validation.
    elsif($result->{repository}{name} eq 'docs' && $result->{ref} eq 'refs/heads/pages-source')
    {
        write_datalog($result);
        system("echo ====================================================================== >>$valilog");
        system("date >>$valilog");
        system("echo Hook on $result->{repository}{name} >>$valilog");
        system("(cd docs ; git pull --no-edit ; cd ..) >>$valilog 2>&1");
        # Regardless of the below we will scan the docs repository for documentation of feature values.
        # We have to do it if any file in docs/_u-feat changes, or if for any language xxx any file in
        # docs/_xxx/feat changes. However, the scanning is relatively fast, so we will do it every time
        # anything in docs changes.
        system("echo ---------------------------------------------------------------------- >>$valilog");
        # Read the current list of documented features so that we can assess the changes.
        system("echo docs '=>' scan documentation of features >>$valilog");
        my $oldfeats = json_file_to_perl('docs-automation/valrules/feats.json');
        system("perl docs-automation/valrules/scan_docs_for_feats.pl 2>>$valilog");
        my $newfeats = json_file_to_perl('docs-automation/valrules/feats.json');
        # Find languages whose list of documented features has changed.
        my %changed;
        my @changed = ();
        my $c = get_changes(\%changed, $oldfeats->{features}, $newfeats->{features});
        if($c)
        {
            push(@changed, 'features');
        }
        else
        {
            system("echo No changes in features. >>$valilog");
        }
        # Read the current list of documented relations so that we can assess the changes.
        system("echo docs '=>' scan documentation of relations >>$valilog");
        my $olddeprels = json_file_to_perl('docs-automation/valrules/deprels.json');
        system("perl docs-automation/valrules/scan_docs_for_deps.pl 2>>$valilog");
        my $newdeprels = json_file_to_perl('docs-automation/valrules/deprels.json');
        # Find languages whose list of documented relations has changed.
        $c = get_changes(\%changed, $olddeprels->{deprels}, $newdeprels->{deprels});
        if($c)
        {
            push(@changed, 'deprels');
        }
        else
        {
            system("echo No changes in dependency relations. >>$valilog");
        }
        # Construct a descriptive git commit message for the changes.
        # It should not be just a language code because then this script would
        # pick it up again and try to re-validate what we're about to validate now.
        my $changed;
        if(scalar(keys(%changed)) > 0)
        {
            $changed = join('/', @changed); # features/deprels
            my @changedlcodes = sort(keys(%changed));
            my $n = scalar(@changedlcodes);
            if($n > 5)
            {
                $changed .= ": $n languages";
            }
            else
            {
                $changed .= ': '.join(',', @changedlcodes);
            }
        }
        # Commit the changes to the repositories and push them to Github.
        # We must do it even if we did not observe a real change. In case any
        # formal aspect changed and the file is different, we need to make sure
        # that the repository is clean and in sync, otherwise future git pulls would fail.
        system("/home/zeman/bin/git-push-docs-automation.sh '$result->{pusher}{name}' '$changed' > /dev/null");
        # Furthermore, a change in language-specific documentation index will also trigger re-validation.
        foreach my $commit (@{$result->{commits}})
        {
            foreach my $file (@{$commit->{added}}, @{$commit->{modified}}, @{$commit->{removed}})
            {
                if($file =~ m:^_([a-z]+)/index\.md$:)
                {
                    my $lcode = $1;
                    $changed{$lcode}++;
                }
            }
        }
        my @changed = sort(keys(%changed));
        if(scalar(@changed) > 0)
        {
            my $changed = join(' ', @changed);
            system("echo Changed: $changed >>$valilog");
            print LOG ("changed = $changed\n");
            # The validation must be performed in a child process. It may take a long
            # time and the web server will kill this process if we exceed the timeout.
            # Call the script through the docs-automation repo so that it can find the YAML file with the list of languages.
            system("perl docs-automation/valdan/validate_all.pl $changed >>$valilog 2>&1");
        }
    }
    #--------------------------------------------------------------------------
    # docs-automation docs-automation docs-automation docs-automation
    #--------------------------------------------------------------------------
    # Change in master branch of repository docs-automation may mean new languages were added or the validation infrastructure modified.
    elsif($result->{repository}{name} eq 'docs-automation' && $result->{ref} eq 'refs/heads/master')
    {
        write_datalog($result);
        system("echo ====================================================================== >>$valilog");
        system("date >>$valilog");
        system("echo Hook on $result->{repository}{name} >>$valilog");
        # When pulling from Github manually, we also run ./valdan/lnquest.sh in order to restore the hard links from the top folder.
        # However, this cannot be done by user www-data who is not trusted enough. So if the critical scripts are changed,
        # they will be updated automatically in the repo but the production version will be detached and kept the same until
        # I go there and manually run lnquest.sh.
        system("(cd docs-automation ; git pull --no-edit ; cd ..) >>$valilog 2>&1");
    }
}
close(LOG);



#------------------------------------------------------------------------------
# Compares lists of permitted features/relations before and after. Reports
# languages that have changed. Marks the languages in a hash supplied by the
# caller. Returns 1 if at least one language changed.
#------------------------------------------------------------------------------
sub get_changes
{
    my $changed = shift; # hash reference: languages with chages
    my $oldhash = shift; # hash reference: permitted before
    my $newhash = shift; # hash reference: permitted after
    my $change = 0;
    foreach my $lcode (keys(%{$oldhash}))
    {
        if(!exists($newhash->{$lcode}))
        {
            $changed->{$lcode}++;
            $change = 1;
        }
        else
        {
            my $oldlist = join(',', sort(grep {$oldhash->{$lcode}{$_}{permitted}} (keys(%{$oldhash->{$lcode}}))));
            my $newlist = join(',', sort(grep {$newhash->{$lcode}{$_}{permitted}} (keys(%{$newhash->{$lcode}}))));
            if($newlist ne $oldlist)
            {
                $changed->{$lcode}++;
                $change = 1;
            }
        }
    }
    foreach my $lcode (keys(%{$newhash}))
    {
        if(!exists($oldhash->{$lcode}))
        {
            $changed->{$lcode}++;
            $change = 1;
        }
    }
    return $change;
}



#------------------------------------------------------------------------------
# Zapíše do logu informace o pushi, na který reagujeme.
#------------------------------------------------------------------------------
sub write_datalog
{
    my $result = shift;
    open(DLOG, ">>log/datalog.txt");
    print DLOG ("\n\n\n-------------------------------------------------------------------------------\n");
    print DLOG ("repository = $result->{repository}{name}\n");
    print DLOG ("ref        = $result->{ref}\n");
    print DLOG ("commit     = $result->{head_commit}{id}\n");
    print DLOG ("message    = $result->{head_commit}{message}\n");
    print DLOG ("timestamp  = $result->{head_commit}{timestamp}\n");
    print DLOG ("pusher     = $result->{pusher}{name}\n");
    print DLOG ("email      = $result->{pusher}{email}\n");
    close(DLOG);
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
<title>Form response</title>
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
# Poor man's JSON::Parse (JSON::Parse is not installed on quest.)
#------------------------------------------------------------------------------
sub jsonparse
{
    my $json = shift;
    my $result;
    # Eat whitespace.
    $json =~ s/^\s+//s;
    if($json =~ m/^\{/)
    {
        ($result, $json) = jsonparse_hash($json);
    }
    elsif($json =~ m/^\[/)
    {
        ($result, $json) = jsonparse_array($json);
    }
    elsif($json =~ m/^"/) #"
    {
        ($result, $json) = jsonparse_string($json);
    }
    elsif($json =~ m/^\d/)
    {
        ($result, $json) = jsonparse_number($json);
    }
    elsif($json =~ m/^(true|false)/i)
    {
        ($result, $json) = jsonparse_boolean($json);
    }
    elsif($json =~ m/^[A-Za-z0-9_]/)
    {
        ($result, $json) = jsonparse_bareword($json);
    }
    return ($result, $json);
}



#------------------------------------------------------------------------------
# Reads a hash from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_hash
{
    my $json = shift;
    my %hash;
    # We must see a curly bracket.
    if(!($json =~ s/^\{//))
    {
        die("Left curly bracket expected at '$json'.");
    }
    # Eat whitespace.
    $json =~ s/^\s+//s;
    unless($json =~ m/^\}/)
    {
        do
        {
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # Read hash key.
            my $key;
            if($json =~ m/^"/) #"
            {
                ($key, $json) = jsonparse_string($json);
            }
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # We must see a colon.
            if(!($json =~ s/^://))
            {
                die("Colon expected at '$json'.");
            }
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # Read hash value.
            my $value;
            ($value, $json) = jsonparse($json);
            $hash{$key} = $value;
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # If we see comma now, there will be more key-value pairs.
        }
        while($json =~ s/^,//);
    }
    # We must see a curly bracket.
    if(!($json =~ s/^\}//))
    {
        die("Right curly bracket expected at '$json'.");
    }
    return (\%hash, $json);
}



#------------------------------------------------------------------------------
# Reads an array from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_array
{
    my $json = shift;
    my @array;
    # We must see a square bracket.
    if(!($json =~ s/^\[//))
    {
        die("Left square bracket expected at '$json'.");
    }
    # Eat whitespace.
    $json =~ s/^\s+//s;
    unless($json =~ m/^\]/)
    {
        do
        {
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # Read array element.
            my $value;
            ($value, $json) = jsonparse($json);
            push(@array, $value);
            # Eat whitespace.
            $json =~ s/^\s+//s;
            # If we see comma now, there will be more elements.
        }
        while($json =~ s/^,//);
    }
    # We must see a square bracket.
    if(!($json =~ s/^\]//))
    {
        die("Right square bracket expected at '$json'.");
    }
    return (\@array, $json);
}



#------------------------------------------------------------------------------
# Reads a string from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_string
{
    my $json = shift;
    # We must see a quotation mark.
    if(!($json =~ s/^"//)) #"
    {
        die("Quotation mark expected at '$json'.");
    }
    my $string;
    while(1)
    {
        $json =~ s/^([^"]+)//s; #"
        $string .= $1;
        # If the quotation mark is preceded by a backslash, it is part of the string.
        if($string =~ m/\\$/ && $json =~ s/^"//) #"
        {
            $string =~ s/\\$/"/; #"
        }
        else
        {
            last;
        }
    }
    # We must see a quotation mark.
    if(!($json =~ s/^"//)) #"
    {
        die("Quotation mark expected at '$json'.");
    }
    return ($string, $json);
}



#------------------------------------------------------------------------------
# Reads a number from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_number
{
    my $json = shift;
    $json =~ s/^(\d+)//s; #"
    my $number = $1;
    return ($number, $json);
}



#------------------------------------------------------------------------------
# Reads a true/false value from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_boolean
{
    my $json = shift;
    my $result;
    if($json =~ s/^true//i)
    {
        $result = 1;
    }
    elsif($json =~ s/^false//i)
    {
        $result = 0;
    }
    else
    {
        die("True/false expected at '$json'.");
    }
    return ($result, $json);
}



#------------------------------------------------------------------------------
# Reads a bareword (e.g. null) from JSON string.
#------------------------------------------------------------------------------
sub jsonparse_bareword # not true and false (for those see above) but e.g. null
{
    my $json = shift;
    my $result;
    if($json =~ s/^([A-Za-z0-9_]+)//)
    {
        $result = $1;
    }
    else
    {
        die("Bareword expected at '$json'.");
    }
    return ($result, $json);
}
