#!/usr/bin/env perl
# A one-time script that prints a JSON version of the existing validation dispensations.
# Copyright © 2021 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

sub usage
{
    print STDERR ("Usage: perl $0 --json dispensations.json\n");
}

my $jsonfile;
GetOptions
(
    'json=s' => \$jsonfile # path to the JSON, e.g., docs-automation/valdan/dispensations.json
);
if(!defined($jsonfile))
{
    usage();
    die("Unknown path to the JSON file");
}



# The following block is copied from update-validation-report.pl.
BEGIN
{
    # List for each folder name tests that this treebank is allowed to fail.
    %exceptions =
    (
        'UD_Amharic-ATT'                => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'right-to-left-goeswith', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Ancient_Greek-PROIEL'       => ['lang-spec-doc', 'leaf-cc', 'orphan-parent', 'aux-lemma'],
        'UD_Ancient_Greek-Perseus'      => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-punct'],
        'UD_Arabic-NYUAD'               => ['aux-lemma'],
        'UD_Arabic-PUD'                 => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-fixed', 'leaf-goeswith', 'leaf-mark-case', 'orphan-parent', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'aux-lemma', 'cop-lemma'],
        'UD_Bambara-CRB'                => ['lang-spec-doc', 'orphan-parent', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-cc', 'aux-lemma'],
        'UD_Basque-BDT'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Breton-KEB'                 => ['lang-spec-doc'],
        'UD_Buryat-BDT'                 => ['orphan-parent', 'rel-upos-advmod', 'rel-upos-aux', 'aux-lemma', 'cop-lemma'],
        'UD_Cantonese-HK'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'aux-lemma'],
        'UD_Catalan-AnCora'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-CFL'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-GSD'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-GSDSimp'            => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-HK'                 => ['lang-spec-doc', 'leaf-aux-cop', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-det'],
        'UD_Chinese-PUD'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-mark', 'rel-upos-nummod'],
        'UD_Danish-DDT'                 => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-goeswith', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cc', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'cop-lemma'],
        'UD_Dutch-Alpino'               => ['punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_Dutch-LassySmall'           => ['punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_English-ESL'                => ['goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-goeswith', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct'],
        'UD_English-EWT'                => ['goeswith-nospace', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod'],
        'UD_Faroese-OFT'                => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'rel-upos-advmod', 'rel-upos-nummod', 'cop-lemma'],
        'UD_Finnish-FTB'                => ['aux-lemma'],
        'UD_French-FTB'                 => ['aux-lemma', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct'],
        'UD_Galician-CTG'               => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct'],
        'UD_Gothic-PROIEL'              => ['lang-spec-doc', 'orphan-parent', 'rel-upos-advmod', 'too-many-subjects'],
        'UD_Hebrew-HTB'                 => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Hindi-HDTB'                 => ['rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Hindi_English-HIENCS'       => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cop', 'rel-upos-punct'],
        'UD_Hungarian-Szeged'           => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'right-to-left-appos', 'orphan-parent', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cc', 'rel-upos-cop', 'cop-lemma'],
        'UD_Indonesian-GSD'             => ['leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct'],
        'UD_Japanese-Modern'            => ['aux-lemma'],
        'UD_Kazakh-KTB'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-GSD'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-Kaist'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-PUD'                 => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-nummod'],
        'UD_Kurmanji-MG'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-mark'],
        'UD_Latin-PROIEL'               => ['leaf-aux-cop', 'orphan-parent', 'rel-upos-advmod', 'rel-upos-aux', 'aux-lemma'],
        'UD_Latin-Perseus'              => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-punct', 'too-many-subjects'],
        'UD_Marathi-UFAL'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-fixed', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Norwegian-NynorskLIA'       => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-punct'],
        'UD_Old_Church_Slavonic-PROIEL' => ['lang-spec-doc', 'orphan-parent'],
        'UD_Old_East_Slavic-TOROT'      => ['orphan-parent'],
        'UD_Old_French-SRCMF'           => ['lang-spec-doc', 'rel-upos-advmod'],
        'UD_Persian-PerDT'              => ['aux-lemma', 'cop-lemma'],
        'UD_Persian-Seraji'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Portuguese-Bosque'          => ['punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_Portuguese-GSD'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Russian-SynTagRus'          => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'cop-lemma'],
        'UD_Spanish-GSD'                => ['leaf-aux-cop', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Spanish-PUD'                => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-fixed', 'leaf-goeswith', 'leaf-mark-case', 'orphan-parent', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct'],
        'UD_Swedish_Sign_Language-SSLC' => ['lang-spec-doc', 'leaf-aux-cop', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod'],
        'UD_Telugu-MTG'                 => ['lang-spec-doc'],
        'UD_Thai-PUD'                   => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-cc'],
        'UD_Turkish-IMST'               => ['leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'too-many-subjects'],
        'UD_Ukrainian-IU'               => ['lang-spec-doc', 'leaf-cc', 'leaf-mark-case'],
        'UD_Urdu-UDTB'                  => ['rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Uyghur-UDT'                 => ['lang-spec-doc', 'goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'aux-lemma', 'cop-lemma'],
        'UD_Vietnamese-VTB'             => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct'],
    );
    %validation_history =
    (
        'aux-lemma'            => ['2018-11-15', 'b54b2dc4'],
        'cop-lemma'            => ['2019-03-25', '63f0c3c0'],
        'goeswith-gap'         => ['2018-11-23', '91a88eda'],
        'goeswith-nospace'     => ['2018-11-23', '91a88eda'],
        'lang-spec-doc'        => ['2018-11-30', '5d57cd86'],
        'leaf-aux-cop'         => ['2019-01-27', '480bdac0'],
        'leaf-cc'              => ['2019-01-27', '480bdac0'],
        'leaf-fixed'           => ['2019-05-24', '562f2b94'],
        'leaf-goeswith'        => ['2019-05-24', '562f2b94'],
        'leaf-mark-case'       => ['2019-01-27', '480bdac0'],
        'leaf-punct'           => ['2019-05-24', '562f2b94'],
        'orphan-parent'        => ['2019-05-25', '8a86f419'],
        'punct-causes-nonproj' => ['2018-11-23', 'f2cac7d2'],
        'punct-is-nonproj'     => ['2018-11-23', 'f2cac7d2'],
        'rel-upos-advmod'      => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-aux'         => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-case'        => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-cc'          => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-cop'         => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-det'         => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-expl'        => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-mark'        => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-nummod'      => ['2018-11-15', 'b54b2dc4'],
        'rel-upos-punct'       => ['2018-11-15', 'b54b2dc4'],
        'right-to-left-appos'  => ['2018-11-15', 'b54b2dc4'],
        'right-to-left-goeswith' => ['2018-11-15', 'b54b2dc4'],
        'upos-rel-punct'       => ['2018-11-15', 'b54b2dc4'],
        'too-many-subjects'    => ['2019-01-17', '829e9143']
    );
}

# Re-hash the dispensations by error types.
my %errors;
my @treebanks = keys(%exceptions);
my $nt = scalar(@treebanks);
foreach my $treebank (@treebanks)
{
    foreach my $error (@{$exceptions{$treebank}})
    {
        $errors{$error}{$treebank}++;
    }
}
my @errors = sort(keys(%errors));
my $n = scalar(@errors);
my $oldest_date;
foreach my $error (@errors)
{
    my $k = scalar(keys(%{$errors{$error}}));
    my $history = 'UNKNOWN';
    if(exists($validation_history{$error}))
    {
        $history = "$validation_history{$error}[0]\t$validation_history{$error}[1]";
        if(!defined($oldest_date) || $validation_history{$error}[0] lt $oldest_date)
        {
            $oldest_date = $validation_history{$error}[0];
        }
    }
    print("$error\t$k\t$history\n");
}
print("Total $n errors that are currently permitted in at least one treebank.\n");
print("Total $nt treebanks that have currently at least one dispensation.\n");
print("The oldest error is from $oldest_date.\n");
# List treebanks that have at least one error dated 2019-05-01 or earlier.
my %oldest_errors;
foreach my $error (@errors)
{
    if(exists($validation_history{$error}) && $validation_history{$error}[0] le '2019-05-01')
    {
        $oldest_errors{$error}++;
    }
}
my @neglected_treebanks;
foreach my $treebank (@treebanks)
{
    foreach my $error (@{$exceptions{$treebank}})
    {
        if(exists($oldest_errors{$error}))
        {
            push(@neglected_treebanks, $treebank);
            last;
        }
    }
}
my $nn = scalar(@neglected_treebanks);
if($nn)
{
    @neglected_treebanks = sort(@neglected_treebanks);
    print("There are $nn treebanks that could be declared NEGLECTED in May 2022 if their oldest errors are not fixed: ", join(', ', @neglected_treebanks), "\n");
}
# Write the JSON file.
my $json = "{\n";
$json .= '"dispensations": {'."\n";
@djsons = ();
foreach my $e (@errors)
{
    if(!exists($validation_history{$e}))
    {
        die("Unknown error '$e'");
    }
    my $date = $validation_history{$e}[0];
    my $commit = $validation_history{$e}[1]; # the first 8 characters of the hash of the corresponding commit to the tools repository
    my @dtreebanks = sort(keys(%{$errors{$e}}));
    my $djson = '"'.$e.'": '.encode_json(['date', $date], ['commit', $commit], ['treebanks', \@dtreebanks, 'list']);
    push(@djsons, $djson);
}
$json .= join(",\n", @djsons)."\n";
$json .= "}\n"; # end of dispensations
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
