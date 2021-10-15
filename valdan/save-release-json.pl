#!/usr/bin/env perl
# Creates a list of treebanks that are included in a UD release and saves the
# list in a JSON file. For various maintenance tasks, we need to know which
# treebank was released when.
# Copyright © 2021 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use JSON::Parse 'json_file_to_perl';

sub usage
{
    print STDERR ("Usage: perl $0 --json releases.json --releasenum 2.8 --releasedate 2021-05-15 --releasedir /net/data/universal-dependencies-2.8\n");
    print STDERR ("    Alternatively, it is possible to list the treebanks as arguments instead of pointing to the\n");
    print STDERR ("    release folder.\n");
}

# We can take the list of treebanks as an argument from the command line. Many
# steps during the release process are based on such a list. Alternatively, we
# can scan the folder with an old release and collect the names of the sub-
# folders.

# --releasedir /net/data/universal-dependencies-2.8 ... take subfolders thereof
my $jsonfile;
my $releasenum;
my $releasedir;
my $releasedate;
GetOptions
(
    'json=s'        => \$jsonfile,   # path to the JSON, e.g., docs-automation/valdan/releases.json
    'releasenum=s'  => \$releasenum, # e.g., 2.8
    'releasedir=s'  => \$releasedir,
    'releasedate=s' => \$releasedate # e.g., 2021-05-15
);

my @treebanks;
if(defined($releasedir))
{
    opendir(DIR, $releasedir) or die("Cannot read folder '$releasedir': $!");
    if($releasenum eq '1.0')
    {
        # In UD 1.0, the treebank folder names did not start with 'UD_'. They were just language codes. Let's hard-list them here, with the UD_names.
        @treebanks = ('UD_Czech', 'UD_English', 'UD_Finnish', 'UD_French', 'UD_German', 'UD_Hungarian', 'UD_Irish', 'UD_Italian', 'UD_Spanish', 'UD_Swedish');
    }
    else
    {
        @treebanks = sort(grep {-d "$releasedir/$_" && m/^UD_.+$/} (readdir(DIR)));
    }
    closedir(DIR);
}
else
{
    @treebanks = sort(grep {m/^UD_.+$/} (@ARGV));
}

if(!defined($jsonfile))
{
    usage();
    die("Unknown path to the JSON file");
}
if(!defined($releasenum))
{
    usage();
    die("Undefined release number");
}
if(scalar(@treebanks) == 0)
{
    usage();
    die("The list of treebanks is empty");
}
if(!defined($releasedate))
{
    usage();
    die("Undefined release date");
}
elsif($releasedate !~ m/^2[0-9][0-9][0-9]-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/)
{
    usage();
    die("Release date '$releasedate' is not formatted YYYY-MM-DD");
}

# Temporary debugging.
print STDERR ("Release number      = $releasenum\n");
print STDERR ("Release date        = $releasedate\n");
print STDERR ("Number of treebanks = ".scalar(@treebanks)."\n");
print STDERR ("List of treebanks   = ".join(', ', @treebanks)."\n");

# If the JSON file already exists, read its current contents.
my $releases = [];
if(-f $jsonfile)
{
    $releases = json_file_to_perl($jsonfile)->{releases};
    my $n = scalar(keys(%{$releases}));
    print STDERR ("The file '$jsonfile' already exists and contains $n releases.\n");
    # Does the file already contain the current release?
    if(exists($releases->{$releasenum}))
    {
        print STDERR ("It already includes an older record for $releasenum. It will be overwritten.\n");
    }
}
else
{
    print STDERR ("The file '$jsonfile' does not exist yet.\n");
}
# Save the current release.
$releases->{$releasenum} = {'date' => $releasedate, 'treebanks' => \@treebanks};
# Write the JSON file.
my $json = "{\n";
$json .= '"releases": {'."\n";
@rjsons = ();
# Order the releases by their release numbers.
my @sorted = sort
{
    my $amaj = $a;
    my $amin = 0;
    my $bmaj = $b;
    my $bmin = 0;
    if($a =~ m/^(\d+)\.(\d+)$/)
    {
        $amaj = $1;
        $amin = $2;
    }
    if($b =~ m/^(\d+)\.(\d+)$/)
    {
        $bmaj = $1;
        $bmin = $2;
    }
    my $r = $amaj <=> $bmaj;
    unless($r)
    {
        $r = $amin <=> $bmin;
    }
    $r
}
(keys(%{$releases}));
my $lastrnum;
my $lastdate;
foreach my $r (@sorted)
{
    # Check that the sequence of dates also matches the sequence of release numbers.
    if(defined($lastdate) && $releases->{$r}{date} le $lastdate)
    {
        print STDERR ("WARNING! Release '$r' has date '$releases->{$r}{date}', which is not greater than '$lastdate' of release '$lastrnum'.\n");
    }
    $lastrnum = $r;
    $lastdate = $releases->{$r}{date};
    my $rjson = '"'.$r.'": '.encode_json(['date', $releases->{$r}{date}], ['treebanks', $releases->{$r}{treebanks}, 'list']);
    push(@rjsons, $rjson);
}
$json .= join(",\n", @rjsons)."\n";
$json .= "}\n"; # end of releases
$json .= "}\n"; # end of JSON
open(JSON, ">$jsonfile") or die("Cannot write '$jsonfile': $!");
print JSON ($json);
close(JSON);



#------------------------------------------------------------------------------
# Takes a list of pairs [name, value] and returns the corresponding JSON
# structure {"name1": "value1", "name2": "value2"}. The pair is an arrayref;
# if there is a third element in the array and it says "numeric", then the
# value is treated as numeric, i.e., it is not enclosed in quotation marks.
# The type in the third position can be also "list" (of strings),
# "list of numeric" and "list of structures".
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
                confess("Unknown value of attribute '$name'");
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
