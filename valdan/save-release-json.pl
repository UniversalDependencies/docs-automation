#!/usr/bin/env perl
# Creates a list of treebanks that are included in a UD release and saves the
# list in a JSON file (while preserving the older releases that were saved in
# the JSON file earlier). For various maintenance tasks, we need to know which
# treebank was released when.
# Copyright © 2021, 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
my $renames = {}; # changes of treebank names after a release (release number is the key)
if(-f $jsonfile)
{
    my $from_json = json_file_to_perl($jsonfile);
    $releases = $from_json->{releases};
    $renames = $from_json->{renamed_after_release};
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
my @sorted = sort_release_numbers(keys(%{$releases}));
get_changes_in_treebank_list($releases, @sorted);
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
    if(defined($releases->{$r}{renamed}) && scalar(@{$releases->{$r}{renamed}}) > 0)
    {
        my @rnmjsons;
        foreach my $rnm (@{$releases->{$r}{renamed}})
        {
            push(@rnmjsons, '["'.escape_json_string($rnm->[0]).'", "'.escape_json_string($rnm->[1]).'"]');
        }
        my $rnmjson = '['.join(', ', @rnmjsons).']'; #{{
        $rjson =~ s/\}$/, /;
        $rjson .= '"renamed": '.$rnmjson.'}';
    }
    push(@rjsons, $rjson);
}
$json .= join(",\n", @rjsons)."\n";
$json .= "},\n"; # end of releases
# Print changes of treebank names after releases.
@rjsons = ();
@sorted = sort_release_numbers(keys(%{$renames}));
foreach my $r (@sorted)
{
    my $rjson = '"'.$r.'": ';
    my @rnmjsons;
    foreach my $rnm (@{$renames->{$r}})
    {
        push(@rnmjsons, '["'.escape_json_string($rnm->[0]).'", "'.escape_json_string($rnm->[1]).'"]');
    }
    my $rnmjson = '['.join(', ', @rnmjsons).']';
    push(@rjsons, $rnmjson);
}
$json .= '"renamed_after_release": {'."\n";
$json .= join(",\n", @rjsons)."\n";
$json .= "}\n"; # end of renames
$json .= "}\n"; # end of JSON
open(JSON, ">$jsonfile") or die("Cannot write '$jsonfile': $!");
print JSON ($json);
close(JSON);



#------------------------------------------------------------------------------
# Sort release numbers.
#------------------------------------------------------------------------------
sub sort_release_numbers
{
    return sort
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
    (@_);
}



#------------------------------------------------------------------------------
# Iterates over the known releases. Looks for treebanks that have disappeared
# and treebanks that newly appeared. This may help to find the rare cases when
# a treebank was renamed.
#------------------------------------------------------------------------------
sub get_changes_in_treebank_list
{
    my $releases = shift; # hash reference
    my @releases = @_; # sorted keys to the hash
    my %treebanks;
    # Assume the releases are sorted chronologically. Check that it is so.
    my $lastrnum;
    my $lastdate;
    foreach my $r (@releases)
    {
        if(defined($lastdate) && $releases->{$r}{date} le $lastdate)
        {
            print STDERR ("WARNING! Release '$r' has date '$releases->{$r}{date}', which is not greater than '$lastdate' of release '$lastrnum'.\n");
        }
        $lastrnum = $r;
        $lastdate = $releases->{$r}{date};
        # Get treebanks that are new in this release.
        my %rtreebanks;
        foreach my $t (@{$releases->{$r}{treebanks}})
        {
            if(!exists($treebanks{$t}))
            {
                print STDERR ("New in release $r: $t\n");
            }
            $rtreebanks{$t}++;
            $treebanks{$t}++;
        }
        # Get treebanks that were in the previous release but are not in this release.
        foreach my $t (sort(keys(%treebanks)))
        {
            if(!exists($rtreebanks{$t}))
            {
                print STDERR ("No longer in release $r: $t\n");
                delete($treebanks{$t});
            }
        }
    }
    ###!!! I am temporarily hard-coding here what this function found.
    ###!!! Later we will want to save it in the JSON file somehow.
    my @name_changes =
    (
        ['1.2',  'UD_Latin-ITT',     '1.3', 'UD_Latin-ITTB'],
        ['1.4',  'UD_Norwegian',     '2.0', 'UD_Norwegian-Bokmaal'],
        ['2.1',  'UD_Afrikaans',     '2.2', 'UD_Afrikaans-AfriBooms'],
        ['2.1',  'UD_Ancient_Greek', '2.2', 'UD_Ancient_Greek-Perseus'],
        ['2.1',  'UD_Arabic',        '2.2', 'UD_Arabic-PADT'],
        ['2.1',  'UD_Basque',        '2.2', 'UD_Basque-BDT'],
        ['2.1',  'UD_Belarusian',    '2.2', 'UD_Belarusian-HSE'],
        ['2.1',  'UD_Bulgarian',     '2.2', 'UD_Bulgarian-BTB'],
        ['2.1',  'UD_Buryat',        '2.2', 'UD_Buryat-BDT'],
        ['2.1',  'UD_Cantonese',     '2.2', 'UD_Cantonese-HK'],
        ['2.1',  'UD_Catalan',       '2.2', 'UD_Catalan-AnCora'],
        ['2.1',  'UD_Chinese',       '2.2', 'UD_Chinese-GSD'],
        ['2.1',  'UD_Coptic',        '2.2', 'UD_Coptic-Scriptorium'],
        ['2.1',  'UD_Croatian',      '2.2', 'UD_Croatian-SET'],
        ['2.1',  'UD_Czech',         '2.2', 'UD_Czech-PDT'],
        ['2.1',  'UD_Danish',        '2.2', 'UD_Danish-DDT'],
        ['2.1',  'UD_Dutch',         '2.2', 'UD_Dutch-Alpino'],
        ['2.1',  'UD_English',       '2.2', 'UD_English-EWT'],
        ['2.1',  'UD_Estonian',      '2.2', 'UD_Estonian-EDT'],
        ['2.1',  'UD_Finnish',       '2.2', 'UD_Finnish-TDT'],
        ['2.1',  'UD_French',        '2.2', 'UD_French-GSD'],
        ['2.1',  'UD_Galician',      '2.2', 'UD_Galician-CTG'],
        ['2.1',  'UD_German',        '2.2', 'UD_German-GSD'],
        ['2.1',  'UD_Gothic',        '2.2', 'UD_Gothic-PROIEL'],
        ['2.1',  'UD_Greek',         '2.2', 'UD_Greek-GDT'],
        ['2.1',  'UD_Hebrew',        '2.2', 'UD_Hebrew-HTB'],
        ['2.1',  'UD_Hindi',         '2.2', 'UD_Hindi-HDTB'],
        ['2.1',  'UD_Hungarian',     '2.2', 'UD_Hungarian-Szeged'],
        ['2.1',  'UD_Indonesian',    '2.2', 'UD_Indonesian-GSD'],
        ['2.1',  'UD_Irish',         '2.2', 'UD_Irish-IDT'],
        ['2.1',  'UD_Italian',       '2.2', 'UD_Italian-ISDT'],
        ['2.1',  'UD_Japanese',      '2.2', 'UD_Japanese-GSD'],
        ['2.1',  'UD_Kazakh',        '2.2', 'UD_Kazakh-KTB'],
        ['2.1',  'UD_Korean',        '2.2', 'UD_Korean-GSD'],
        ['2.1',  'UD_Kurmanji',      '2.2', 'UD_Kurmanji-MG'],
        ['2.1',  'UD_Latin',         '2.2', 'UD_Latin-Perseus'],
        ['2.1',  'UD_Latvian',       '2.2', 'UD_Latvian-LVTB'],
        ['2.1',  'UD_Lithuanian',    '2.2', 'UD_Lithuanian-HSE'],
        ['2.1',  'UD_Marathi',       '2.2', 'UD_Marathi-UFAL'],
        ['2.1',  'UD_North_Sami',    '2.2', 'UD_North_Sami-Giella'],
        ['2.1',  'UD_Old_Church_Slavonic', '2.2', 'UD_Old_Church_Slavonic-PROIEL'],
        ['2.1',  'UD_Persian',       '2.2', 'UD_Persian-Seraji'],
        ['2.1',  'UD_Polish',        '2.2', 'UD_Polish-SZ'],
        ['2.1',  'UD_Portuguese',    '2.2', 'UD_Portuguese-Bosque'],
        ['2.1',  'UD_Portuguese-BR', '2.2', 'UD_Portuguese-GSD'],
        ['2.1',  'UD_Romanian',      '2.2', 'UD_Romanian-RRT'],
        ['2.1',  'UD_Russian',       '2.2', 'UD_Russian-GSD'],
        ['2.1',  'UD_Sanskrit',      '2.2', 'UD_Sanskrit-UFAL'],
        ['2.1',  'UD_Serbian',       '2.2', 'UD_Serbian-SET'],
        ['2.1',  'UD_Slovak',        '2.2', 'UD_Slovak-SNK'],
        ['2.1',  'UD_Slovenian',     '2.2', 'UD_Slovenian-SSJ'],
        ['2.1',  'UD_Spanish',       '2.2', 'UD_Spanish-GSD'],
        ['2.1',  'UD_Swedish',       '2.2', 'UD_Swedish-Talbanken'],
        ['2.1',  'UD_Swedish_Sign_Language', '2.2', 'UD_Swedish_Sign_Language-SSLC'],
        ['2.1',  'UD_Tamil',         '2.2', 'UD_Tamil-TTB'],
        ['2.1',  'UD_Telugu',        '2.2', 'UD_Telugu-MTG'],
        ['2.1',  'UD_Turkish',       '2.2', 'UD_Turkish-IMST'],
        ['2.1',  'UD_Ukrainian',     '2.2', 'UD_Ukrainian-IU'],
        ['2.1',  'UD_Upper_Sorbian', '2.2', 'UD_Upper_Sorbian-UFAL'],
        ['2.1',  'UD_Urdu',          '2.2', 'UD_Urdu-UDTB'],
        ['2.1',  'UD_Uyghur',        '2.2', 'UD_Uyghur-UDT'],
        ['2.1',  'UD_Vietnamese',    '2.2', 'UD_Vietnamese-VTB'],
        ['2.3',  'UD_Polish-SZ',         '2.4',  'UD_Polish-PDB'],
        ['2.7',  'UD_Old_Russian-RNC',   '2.8',  'UD_Old_East_Slavic-RNC'],
        ['2.7',  'UD_Old_Russian-TOROT', '2.8',  'UD_Old_East_Slavic-TOROT'],
        ['2.8',  'UD_French-Spoken',     '2.9',  'UD_French-ParisStories'],
        ['2.12', 'UD_Old_French-SRCMF',  '2.13', 'UD_Old_French-PROFITEROLE']
    );
    # Save name changes with the releases.
    foreach my $r (@releases)
    {
        my @rchanges;
        foreach my $nc (@name_changes)
        {
            # Is this release where the new name appeared for the first time?
            if($nc->[2] eq $r)
            {
                push(@rchanges, [$nc->[1], $nc->[3]]);
            }
        }
        $releases->{$r}{renamed} = \@rchanges;
    }
}



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
