#!/usr/bin/env perl
# Receives notifications from Github about new pushes to UD repositories.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
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
    if($result->{repository}{name} =~ m/^UD_/)
    {
        write_datalog($result);
        system("echo ====================================================================== >>$valilog");
        system("date >>$valilog");
        system("echo Hook on $result->{repository}{name} >>$valilog");
        # Now we must update our copy of that repository and update validation status.
        my $folder = $result->{repository}{name};
        system("perl update-validation-report.pl $folder >>$valilog 2>&1");
    }
    elsif($result->{repository}{name} eq 'tools')
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
        foreach my $commit (@{$result->{commits}})
        {
            foreach my $file (@{$commit->{added}}, @{$commit->{modified}})
            {
                if($file eq 'validate.py')
                {
                    $revalidate_all = 1;
                    last;
                }
                elsif($file =~ m-^data/(deprel|feat_val|tokens_w_space)\.(.+)$-)
                {
                    my $ltcode = $2;
                    $changed{$ltcode}++;
                }
            }
        }
        my @changed = sort(keys(%changed));
        if($revalidate_all)
        {
            print LOG ("changed = validate.py\n");
            system("perl validate_all.pl >>$valilog 2>&1");
        }
        elsif(scalar(@changed) > 0)
        {
            print LOG ("changed = ".join(' ', @changed)."\n");
            my @folders = list_ud_folders();
            foreach my $folder (@folders)
            {
                my $record = get_ud_files_and_codes($folder);
                if(exists($changed{$record->{lcode}}))
                {
                    system("perl update-validation-report.pl $folder >>$valilog 2>&1");
                }
            }
        }
    }
}
close(LOG);



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
    $json =~ s/^([^"]+)//s; #"
    my $string = $1;
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



#==============================================================================
# The following functions are available in tools/udlib.pm. However, udlib uses
# JSON::Parse, which is not installed on quest, so we cannot use it here.
#==============================================================================



#------------------------------------------------------------------------------
# Returns list of UD_* folders in a given folder. Default: the current folder.
#------------------------------------------------------------------------------
sub list_ud_folders
{
    my $path = shift;
    $path = '.' if(!defined($path));
    opendir(DIR, $path) or die("Cannot read the contents of '$path': $!");
    my @folders = sort(grep {-d "$path/$_" && m/^UD_.+/} (readdir(DIR)));
    closedir(DIR);
    return @folders;
}



#------------------------------------------------------------------------------
# Scans a UD folder for CoNLL-U files. Uses the file names to guess the
# language code.
#------------------------------------------------------------------------------
sub get_ud_files_and_codes
{
    my $udfolder = shift; # e.g. "UD_Czech"; not the full path
    my $path = shift; # path to the superordinate folder; default: the current folder
    $path = '.' if(!defined($path));
    my $name;
    my $langname;
    my $tbkext;
    if($udfolder =~ m/^UD_(([^-]+)(?:-(.+))?)$/)
    {
        $name = $1;
        $langname = $2;
        $tbkext = $3;
        $langname =~ s/_/ /g;
    }
    else
    {
        print STDERR ("WARNING: Unexpected folder name '$udfolder'\n");
    }
    # Look for training, development or test data.
    my $section = 'any'; # training|development|test|any
    my %section_re =
    (
        # Training data in UD_Czech are split to four files.
        'training'    => 'train(-[clmv])?',
        'development' => 'dev',
        'test'        => 'test',
        'any'         => '(train(-[clmv])?|dev|test)'
    );
    opendir(DIR, "$path/$udfolder") or die("Cannot read the contents of '$path/$udfolder': $!");
    my @files = sort(grep {-f "$path/$udfolder/$_" && m/.+-ud-$section_re{$section}\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    my $n = scalar(@files);
    my $code;
    my $lcode;
    my $tcode;
    if($n>0)
    {
        if($n>1 && $section ne 'any')
        {
            print STDERR ("WARNING: Folder '$path/$udfolder' contains multiple ($n) files that look like $section data.\n");
        }
        $files[0] =~ m/^(.+)-ud-$section_re{$section}\.conllu$/;
        $lcode = $code = $1;
        if($code =~ m/^([^_]+)_(.+)$/)
        {
            $lcode = $1;
            $tcode = $2;
        }
    }
    my %record =
    (
        'folder' => $udfolder,
        'name'   => $name,
        'lname'  => $langname,
        'tname'  => $tbkext,
        'code'   => $code,
        'ltcode' => $code, # for compatibility with some tools, this code is provided both as 'code' and as 'ltcode'
        'lcode'  => $lcode,
        'tcode'  => $tcode,
        'files'  => \@files,
        $section => $files[0]
    );
    #print STDERR ("$udfolder\tlname $langname\ttname $tbkext\tcode $code\tlcode $lcode\ttcode $tcode\t$section $files[0]\n");
    return \%record;
}
