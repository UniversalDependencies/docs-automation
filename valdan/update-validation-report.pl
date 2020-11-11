#!/usr/bin/env perl
# Updates the validation report line of a particular treebank.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');



my $folder = $ARGV[0];
exit if(!defined($folder));
$folder =~ s:/$::;
$folder =~ s:^\./::;
system("cd $folder ; (git pull --no-edit >/dev/null 2>&1) ; cd ..");
my $record = get_ud_files_and_codes($folder);
my $treebank_message;
my %error_stats;
if(scalar(@{$record->{files}}) > 0)
{
    my $folder_success = 1;
    system("date > log/$folder.log 2>&1");
    # Check list of files and metadata in README.
    my $command = "tools/check_files.pl $folder";
    system("echo $command >> log/$folder.log");
    my $result = saferun("perl -I perllib/lib/perl5 -I perllib/lib/perl5/x86_64-linux-gnu-thread-multi $command >> log/$folder.log 2>&1");
    $folder_success = $folder_success && $result;
    # Check individual data files.
    foreach my $file (@{$record->{files}})
    {
        $command = "./validate.sh --lang $record->{lcode} --max-err 0 $folder/$file";
        system("echo $command >> log/$folder.log");
        $result = saferun("$command >> log/$folder.log 2>&1");
        $folder_success = $folder_success && $result;
    }
    count_error_types("log/$folder.log", \%error_stats);
    my @error_types = sort(keys(%error_stats));
    my @testids = map {my @f = split(/\s+/, $_); $f[2]} (@error_types);
    my $error_stats = '';
    my $legacy_status = 'ERROR';
    if(scalar(@error_types) > 0)
    {
        my $total = 0;
        foreach my $error_type (@error_types)
        {
            $total += $error_stats{$error_type};
        }
        # Error types include level, class, and test id, e.g., "L3 Syntax leaf-mark-case".
        $error_stats = ' ('.join('; ', ("TOTAL $total", map {"$_ $error_stats{$_}"} (@error_types))).')';
        $legacy_status = get_legacy_status($folder, \@testids);
    }
    $treebank_message = "$folder: ";
    $treebank_message .= $folder_success ? 'VALID' : $legacy_status.$error_stats;
    my @unused = get_unused_exceptions($folder, \@testids);
    if(scalar(@unused) > 0)
    {
        $treebank_message .= ' UNEXCEPT '.join(' ', @unused);
    }
}
else
{
    $treebank_message = "$folder: EMPTY";
}
print STDERR ("$treebank_message\n");
# Update the validation report that comprises all treebanks.
my %valreps;
open(REPORT, "validation-report.txt");
while(<REPORT>)
{
    s/\r?\n$//;
    if(m/^(UD_.+?):/)
    {
        $valreps{$1} = $_;
    }
}
close(REPORT);
$valreps{$folder} = $treebank_message;
my @treebanks = sort(keys(%valreps));
###!!! This is still not safe enough! If two processes try to modify the file at the same time, it can get corrupt!
system("cp validation-report.txt validation-report.bak");
open(REPORT, ">validation-report.txt");
foreach my $treebank (@treebanks)
{
    print REPORT ("$valreps{$treebank}\n");
}
close(REPORT);



#------------------------------------------------------------------------------
# Reads the output of the validator and counts the occurrences of each type of
# error. Adds the counts to a hash provided by the caller.
#------------------------------------------------------------------------------
sub count_error_types
{
    my $logfilename = shift;
    my $stats = shift; # hash ref
    open(LOG, $logfilename) or die("Cannot read $logfilename: $!");
    while(<LOG>)
    {
        if(m/\[(L\d \w+ [-a-z0-9]+)\]/)
        {
            my $error_type = $1;
            $stats->{$error_type}++;
        }
    }
    close(LOG);
}



BEGIN
{
    # List for each folder name tests that this treebank is allowed to fail.
    %exceptions =
    (
        'UD_Afrikaans-AfriBooms'        => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-aux', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Akkadian-PISANDUB'          => ['leaf-mark-case', 'right-to-left-appos', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark'],
        'UD_Amharic-ATT'                => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'right-to-left-goeswith', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Ancient_Greek-PROIEL'       => ['lang-spec-doc', 'leaf-cc', 'orphan-parent', 'aux-lemma'],
        'UD_Ancient_Greek-Perseus'      => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct'],
        'UD_Arabic-NYUAD'               => ['aux-lemma'],
        'UD_Arabic-PUD'                 => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-fixed', 'leaf-goeswith', 'leaf-mark-case', 'orphan-parent', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'aux-lemma', 'cop-lemma'],
        'UD_Bambara-CRB'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-punct', 'aux-lemma'],
        'UD_Basque-BDT'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Breton-KEB'                 => ['lang-spec-doc'],
        'UD_Buryat-BDT'                 => ['lang-spec-doc', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-punct', 'orphan-parent', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Cantonese-HK'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'aux-lemma', 'cop-lemma'],
        'UD_Catalan-AnCora'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-compound', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-CFL'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-GSD'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-GSDSimp'            => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Chinese-HK'                 => ['lang-spec-doc', 'leaf-aux-cop', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-det'],
        'UD_Chinese-PUD'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-mark', 'rel-upos-nummod'],
        'UD_Danish-DDT'                 => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-goeswith', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cc', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'cop-lemma'],
        'UD_Dutch-Alpino'               => ['leaf-aux-cop', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-det'],
        'UD_Dutch-LassySmall'           => ['leaf-mark-case', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_English-ESL'                => ['goeswith-gap', 'leaf-aux-cop', 'leaf-cc', 'leaf-goeswith', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct'],
        'UD_English-EWT'                => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-punct', 'right-to-left-appos', 'right-to-left-goeswith', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-compound', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'upos-rel-punct'],
        'UD_Faroese-OFT'                => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-nummod', 'cop-lemma'],
        'UD_Finnish-FTB'                => ['aux-lemma'],
        'UD_French-FTB'                 => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct'],
        'UD_Galician-CTG'               => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct'],
        'UD_Gothic-PROIEL'              => ['lang-spec-doc', 'orphan-parent', 'rel-upos-advmod', 'too-many-subjects'],
        'UD_Hebrew-HTB'                 => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Hindi-HDTB'                 => ['rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Hindi-PUD'                  => ['right-to-left-appos', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct'],
        'UD_Hindi_English-HIENCS'       => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cop', 'rel-upos-punct'],
        'UD_Hungarian-Szeged'           => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cc', 'rel-upos-cop', 'upos-rel-punct', 'cop-lemma'],
        'UD_Indonesian-GSD'             => ['leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma'],
        'UD_Japanese-Modern'            => ['aux-lemma'],
        'UD_Kazakh-KTB'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-GSD'                 => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-Kaist'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Korean-PUD'                 => ['lang-spec-doc', 'goeswith-gap', 'leaf-aux-cop', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-nummod'],
        'UD_Kurmanji-MG'                => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-mark'],
        'UD_Latin-PROIEL'               => ['leaf-aux-cop', 'orphan-parent', 'rel-upos-advmod', 'rel-upos-aux', 'aux-lemma'],
        'UD_Latin-Perseus'              => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cop', 'rel-upos-mark', 'rel-upos-punct', 'too-many-subjects'],
        'UD_Marathi-UFAL'               => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Norwegian-Bokmaal'          => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_Norwegian-Nynorsk'          => ['lang-spec-doc', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark'],
        'UD_Norwegian-NynorskLIA'       => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-punct'],
        'UD_Old_Church_Slavonic-PROIEL' => ['lang-spec-doc', 'orphan-parent'],
        'UD_Old_French-SRCMF'           => ['lang-spec-doc', 'rel-upos-advmod'],
        'UD_Old_Russian-TOROT'          => ['orphan-parent'],
        'UD_Persian-PerDT'              => ['aux-lemma'],
        'UD_Persian-Seraji'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Portuguese-Bosque'          => ['punct-causes-nonproj', 'punct-is-nonproj'],
        'UD_Portuguese-GSD'             => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Russian-SynTagRus'          => ['leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-expl', 'rel-upos-mark', 'rel-upos-nummod', 'upos-rel-punct', 'cop-lemma'],
        'UD_Spanish-GSD'                => ['leaf-aux-cop', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Spanish-PUD'                => ['goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-fixed', 'leaf-goeswith', 'leaf-mark-case', 'orphan-parent', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct'],
        'UD_Swedish_Sign_Language-SSLC' => ['lang-spec-doc', 'leaf-aux-cop', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod'],
        'UD_Telugu-MTG'                 => ['lang-spec-doc'],
        'UD_Thai-PUD'                   => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cc', 'rel-upos-mark'],
        'UD_Turkish-IMST'               => ['leaf-aux-cop', 'leaf-cc', 'leaf-fixed', 'leaf-mark-case', 'leaf-punct', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Ukrainian-IU'               => ['lang-spec-doc', 'leaf-cc', 'leaf-mark-case', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-nummod'],
        'UD_Urdu-UDTB'                  => ['rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-compound', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'upos-rel-punct', 'aux-lemma', 'cop-lemma'],
        'UD_Uyghur-UDT'                 => ['lang-spec-doc', 'goeswith-gap', 'goeswith-nospace', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'orphan-parent', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-case', 'rel-upos-cc', 'rel-upos-compound', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-nummod', 'rel-upos-punct', 'too-many-subjects', 'aux-lemma', 'cop-lemma'],
        'UD_Vietnamese-VTB'             => ['lang-spec-doc', 'leaf-aux-cop', 'leaf-cc', 'leaf-mark-case', 'leaf-punct', 'right-to-left-appos', 'punct-causes-nonproj', 'punct-is-nonproj', 'rel-upos-advmod', 'rel-upos-aux', 'rel-upos-cop', 'rel-upos-det', 'rel-upos-mark', 'rel-upos-punct', 'upos-rel-punct'],
    );



    # We need to know for each treebank what is the last valid release that could be used in case of problems with the current data.
    # For most treebanks, release 2.4 does not count as valid because some errors that were already reported were forgiven at once.
    %last_valid_release =
    (
        'UD_Apurina-UFPA'               => '2.7',
        'UD_Afrikaans-AfriBooms'        => '2.7',
        'UD_Akkadian-PISANDUB'          => '2.7',
        'UD_Akkadian-RIAO'              => '2.7',
        'UD_Akuntsu-TuDeT'              => '2.7',
        'UD_Albanian-TSA'               => '2.7',
        'UD_Amharic-ATT'                => '2.7',
        'UD_Ancient_Greek-PROIEL'       => '2.7',
        'UD_Ancient_Greek-Perseus'      => '2.7',
        'UD_Arabic-NYUAD'               => '2.7',
        'UD_Arabic-PADT'                => '2.7',
        'UD_Arabic-PUD'                 => '2.7',
        'UD_Armenian-ArmTDP'            => '2.7',
        'UD_Assyrian-AS'                => '2.7',
        'UD_Bambara-CRB'                => '2.7',
        'UD_Basque-BDT'                 => '2.7',
        'UD_Belarusian-HSE'             => '2.7',
        'UD_Bhojpuri-BHTB'              => '2.7',
        'UD_Breton-KEB'                 => '2.7',
        'UD_Bulgarian-BTB'              => '2.7',
        'UD_Buryat-BDT'                 => '2.7',
        'UD_Cantonese-HK'               => '2.7',
        'UD_Catalan-AnCora'             => '2.7',
        'UD_Chinese-CFL'                => '2.7',
        'UD_Chinese-GSD'                => '2.7',
        'UD_Chinese-GSDSimp'            => '2.7',
        'UD_Chinese-HK'                 => '2.7',
        'UD_Chinese-PUD'                => '2.7',
        'UD_Chukchi-HSE'                => '2.7',
        'UD_Classical_Chinese-Kyoto'    => '2.7',
        'UD_Coptic-Scriptorium'         => '2.7',
        'UD_Croatian-SET'               => '2.7',
        'UD_Czech-CAC'                  => '2.7',
        'UD_Czech-CLTT'                 => '2.7',
        'UD_Czech-FicTree'              => '2.7',
        'UD_Czech-PDT'                  => '2.7',
        'UD_Czech-PUD'                  => '2.7',
        'UD_Danish-DDT'                 => '2.7',
        'UD_Dutch-Alpino'               => '2.7',
        'UD_Dutch-LassySmall'           => '2.7',
        'UD_English-ESL'                => '2.7',
        'UD_English-EWT'                => '2.7',
        'UD_English-GUM'                => '2.7',
        'UD_English-GUMReddit'          => '2.7',
        'UD_English-LinES'              => '2.7',
        'UD_English-PUD'                => '2.7',
        'UD_English-ParTUT'             => '2.7',
        'UD_English-Pronouns'           => '2.7',
        'UD_Erzya-JR'                   => '2.7',
        'UD_Estonian-EDT'               => '2.7',
        'UD_Estonian-EWT'               => '2.7',
        'UD_Faroese-FarPaHC'            => '2.7',
        'UD_Faroese-OFT'                => '2.7',
        'UD_Finnish-FTB'                => '2.7',
        'UD_Finnish-OOD'                => '2.7',
        'UD_Finnish-PUD'                => '2.7',
        'UD_Finnish-TDT'                => '2.7',
        'UD_French-FQB'                 => '2.7',
        'UD_French-FTB'                 => '2.7',
        'UD_French-GSD'                 => '2.7',
        'UD_French-PUD'                 => '2.7',
        'UD_French-ParTUT'              => '2.7',
        'UD_French-Sequoia'             => '2.7',
        'UD_French-Spoken'              => '2.7',
        'UD_Galician-CTG'               => '2.7',
        'UD_Galician-TreeGal'           => '2.7',
        'UD_German-GSD'                 => '2.7',
        'UD_German-HDT'                 => '2.7',
        'UD_German-LIT'                 => '2.7',
        'UD_German-PUD'                 => '2.7',
        'UD_Gothic-PROIEL'              => '2.7',
        'UD_Greek-GDT'                  => '2.7',
        'UD_Hebrew-HTB'                 => '2.7',
        'UD_Hindi-HDTB'                 => '2.7',
        'UD_Hindi-PUD'                  => '2.7',
        'UD_Hindi_English-HIENCS'       => '2.7',
        'UD_Hungarian-Szeged'           => '2.7',
        'UD_Icelandic-IcePaHC'          => '2.7',
        'UD_Icelandic-PUD'              => '2.7',
        'UD_Indonesian-CSUI'            => '2.7',
        'UD_Indonesian-GSD'             => '2.7',
        'UD_Indonesian-PUD'             => '2.7',
        'UD_Irish-IDT'                  => '2.7',
        'UD_Italian-ISDT'               => '2.7',
        'UD_Italian-PUD'                => '2.7',
        'UD_Italian-ParTUT'             => '2.7',
        'UD_Italian-PoSTWITA'           => '2.7',
        'UD_Italian-TWITTIRO'           => '2.7',
        'UD_Italian-VIT'                => '2.7',
        'UD_Japanese-BCCWJ'             => '2.7',
        'UD_Japanese-GSD'               => '2.7',
        'UD_Japanese-KTC'               => '1.4',
        'UD_Japanese-Modern'            => '2.7',
        'UD_Japanese-PUD'               => '2.7',
        'UD_Karelian-KKPP'              => '2.7',
        'UD_Kazakh-KTB'                 => '2.7',
        'UD_Khunsari-AHA'               => '2.7',
        'UD_Komi_Permyak-UH'            => '2.7',
        'UD_Komi_Zyrian-IKDP'           => '2.7',
        'UD_Komi_Zyrian-Lattice'        => '2.7',
        'UD_Korean-GSD'                 => '2.7',
        'UD_Korean-Kaist'               => '2.7',
        'UD_Korean-PUD'                 => '2.7',
        'UD_Kurmanji-MG'                => '2.7',
        'UD_Latin-ITTB'                 => '2.7',
        'UD_Latin-LLCT'                 => '2.7',
        'UD_Latin-PROIEL'               => '2.7',
        'UD_Latin-Perseus'              => '2.7',
        'UD_Latvian-LVTB'               => '2.7',
        'UD_Lithuanian-ALKSNIS'         => '2.7',
        'UD_Lithuanian-HSE'             => '2.7',
        'UD_Livvi-KKPP'                 => '2.7',
        'UD_Maltese-MUDT'               => '2.7',
        'UD_Manx-Cadhan'                => '2.7',
        'UD_Marathi-UFAL'               => '2.7',
        'UD_Mbya_Guarani-Dooley'        => '2.7',
        'UD_Mbya_Guarani-Thomas'        => '2.7',
        'UD_Moksha-JR'                  => '2.7',
        'UD_Munduruku-TuDeT'            => '2.7',
        'UD_Naija-NSC'                  => '2.7',
        'UD_Nayini-AHA'                 => '2.7',
        'UD_North_Sami-Giella'          => '2.7',
        'UD_Norwegian-Bokmaal'          => '2.7',
        'UD_Norwegian-Nynorsk'          => '2.7',
        'UD_Norwegian-NynorskLIA'       => '2.7',
        'UD_Old_Church_Slavonic-PROIEL' => '2.7',
        'UD_Old_French-SRCMF'           => '2.7',
        'UD_Old_Russian-RNC'            => '2.7',
        'UD_Old_Russian-TOROT'          => '2.7',
        'UD_Old_Turkish-Tonqq'          => '2.7',
        'UD_Persian-PerDT'              => '2.7',
        'UD_Persian-Seraji'             => '2.7',
        'UD_Polish-LFG'                 => '2.7',
        'UD_Polish-PDB'                 => '2.7',
        'UD_Polish-PUD'                 => '2.7',
        'UD_Portuguese-Bosque'          => '2.7',
        'UD_Portuguese-GSD'             => '2.7',
        'UD_Portuguese-PUD'             => '2.7',
        'UD_Romanian-Nonstandard'       => '2.7',
        'UD_Romanian-RRT'               => '2.7',
        'UD_Romanian-SiMoNERo'          => '2.7',
        'UD_Russian-GSD'                => '2.7',
        'UD_Russian-PUD'                => '2.7',
        'UD_Russian-SynTagRus'          => '2.7',
        'UD_Russian-Taiga'              => '2.7',
        'UD_Sanskrit-UFAL'              => '2.7',
        'UD_Sanskrit-Vedic'             => '2.7',
        'UD_Scottish_Gaelic-ARCOSG'     => '2.7',
        'UD_Serbian-SET'                => '2.7',
        'UD_Skolt_Sami-Giellagas'       => '2.7',
        'UD_Slovak-SNK'                 => '2.7',
        'UD_Slovenian-SSJ'              => '2.7',
        'UD_Slovenian-SST'              => '2.7',
        'UD_Soi-AHA'                    => '2.7',
        'UD_South_Levantine_Arabic-MADAR' => '2.7',
        'UD_Spanish-AnCora'             => '2.7',
        'UD_Spanish-GSD'                => '2.7',
        'UD_Spanish-PUD'                => '2.7',
        'UD_Swedish-LinES'              => '2.7',
        'UD_Swedish-PUD'                => '2.7',
        'UD_Swedish-Talbanken'          => '2.7',
        'UD_Swedish_Sign_Language-SSLC' => '2.7',
        'UD_Swiss_German-UZH'           => '2.7',
        'UD_Tagalog-TRG'                => '2.7',
        'UD_Tagalog-Ugnayan'            => '2.7',
        'UD_Tamil-MWTT'                 => '2.7',
        'UD_Tamil-TTB'                  => '2.7',
        'UD_Telugu-MTG'                 => '2.7',
        'UD_Thai-PUD'                   => '2.7',
        'UD_Tupinamba-TuDeT'            => '2.7',
        'UD_Turkish-BOUN'               => '2.7',
        'UD_Turkish-GB'                 => '2.7',
        'UD_Turkish-IMST'               => '2.7',
        'UD_Turkish-PUD'                => '2.7',
        'UD_Turkish_German-SAGT'        => '2.7',
        'UD_Ukrainian-IU'               => '2.7',
        'UD_Upper_Sorbian-UFAL'         => '2.7',
        'UD_Urdu-UDTB'                  => '2.7',
        'UD_Uyghur-UDT'                 => '2.7',
        'UD_Vietnamese-VTB'             => '2.7',
        'UD_Warlpiri-UFAL'              => '2.7',
        'UD_Welsh-CCG'                  => '2.7',
        'UD_Wolof-WTB'                  => '2.7',
        'UD_Yoruba-YTB'                 => '2.7'
    );
}



#------------------------------------------------------------------------------
# If a treebank has been valid and part of a previous release, it can be
# granted the "legacy" status. If a new test is introduced and the treebank
# does not pass it, it can still be part of future releases. However, once
# a treebank passes the test, it will never be allowed to fail this test again.
# That is why the list of exceptions is different for each treebank.
#------------------------------------------------------------------------------
sub get_legacy_status
{
    my $folder = shift;
    my $error_types = shift; # array ref
    my @error_types = @{$error_types};
    if(scalar(@error_types) == 0)
    {
        return 'VALID';
    }
    my @exceptions = @{$exceptions{$folder}};
    my @unforgivable = ();
    print STDERR ("Forgivable exceptions for $folder: ".join(' ', @exceptions)."\n");
    foreach my $error_type (@error_types)
    {
        unless(grep {$_ eq $error_type} (@exceptions))
        {
            push(@unforgivable, $error_type);
            print STDERR ("Unforgivable error '$error_type'\n");
        }
    }
    if(scalar(@unforgivable) == 0)
    {
        return 'LEGACY';
    }
    # If we are here, there are new errors that prevent the data from being released.
    # But maybe there is an older release that could be re-released.
    # Only 2.* releases can be used as backup. Discard Japanese KTC, which was last valid in 1.4.
    if($last_valid_release{$folder} =~ m/^2\.\d+$/)
    {
        return "ERROR; BACKUP $last_valid_release{$folder}";
    }
    else
    {
        return 'ERROR; DISCARD';
    }
}



#------------------------------------------------------------------------------
# Checks the list of legacy exceptions against the current list of errors and
# returns exceptions that are no longer needed. If we have just released the
# treebank, these exceptions should be removed and not granted in the future.
#------------------------------------------------------------------------------
sub get_unused_exceptions
{
    my $folder = shift;
    my $error_types = shift; # array ref
    my @error_types = @{$error_types};
    my @exceptions = @{$exceptions{$folder}};
    my @unused = ();
    foreach my $exception (@exceptions)
    {
        unless(grep {$_ eq $exception} (@error_types))
        {
            push(@unused, $exception);
        }
    }
    return @unused;
}



#------------------------------------------------------------------------------
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# This function comes from Dan's library dzsys. I do not want to depend on that
# library here, so I am copying the function. I have also modified it so that
# it does not throw exceptions.
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# Calls an external program. Uses system(). In addition, echoes the command
# line to the standard error output, and returns true/false according to
# whether the call was successful and the external program returned 0 (success)
# or non-zero (error).
#
# Typically called as follows:
#     saferun($command) or die;
#------------------------------------------------------------------------------
sub saferun
{
    my $command = join(' ', @_);
    #my $ted = cas::ted()->{datumcas};
    #print STDERR ("[$ted] Executing: $command\n");
    system($command);
    # The external program does not exist, is not executable or the execution failed for other reasons.
    if($?==-1)
    {
        print STDERR ("ERROR: Failed to execute: $command\n  $!\n");
        return;
    }
    # We were able to start the external program but its execution failed.
    elsif($? & 127)
    {
        printf STDERR ("ERROR: Execution of: $command\n  died with signal %d, %s coredump\n",
            ($? & 127), ($? & 128) ? 'with' : 'without');
        return;
    }
    # The external program ended "successfully" (this still does not guarantee
    # that the external program returned zero!)
    else
    {
        my $exitcode = $? >> 8;
        print STDERR ("Exit code: $exitcode\n") if($exitcode);
        # Return false if the program returned a non-zero value.
        # It is up to the caller how they will handle the return value.
        # (The easiest is to always write:
        # saferun($command) or die;
        # )
        return ! $exitcode;
    }
}



#==============================================================================
# The following functions are available in tools/udlib.pm. However, udlib uses
# JSON::Parse, which is not installed on quest, so we cannot use it here.
# Moreover, I have modified the functions here and they are no longer
# equivalent to the original in udlib.pm.
#==============================================================================



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
    opendir(DIR, "$path/$udfolder") or die("Cannot read the contents of '$path/$udfolder': $!");
    my @files = sort(grep {-f "$path/$udfolder/$_" && m/\.conllu$/i} (readdir(DIR)));
    closedir(DIR);
    my $n = scalar(@files);
    my $code;
    my $lcode;
    my $tcode;
    if($n==0)
    {
        print STDERR ("WARNING: No data found in '$path/$udfolder'\n");
    }
    else
    {
        # Extract the language code and treebank code from the first file name.
        $files[0] =~ m/^(.+)-ud-.+\.conllu$/;
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
        'files'  => \@files
    );
    return \%record;
}
