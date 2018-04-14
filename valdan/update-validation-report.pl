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
my $stmessage = 'not in shared task: no test data';
if(scalar(@{$record->{files}}) > 0)
{
    my $folder_success = 1;
    system("date > log/$folder.log 2>&1");
    foreach my $file (@{$record->{files}})
    {
        my $command = "./validate.sh --lang $record->{lcode} --max-err=10 $folder/$file";
        system("echo $command >> log/$folder.log");
        my $result = saferun("$command >> log/$folder.log 2>&1");
        $folder_success = $folder_success && $result;
        # Test additional requirements on shared task treebanks.
        if($file =~ m/test/)
        {
            print STDERR ("Testing shared task requirements on $folder/$file...\n");
            #my $stresult = saferun("perl test-shared-task.pl $folder/$file");
            #print STDERR ("result = $stresult\n");
            $stmessage = `perl test-shared-task.pl $folder/$file`;
            $stmessage =~ s/\r?\n$//;
        }
    }
    ###!!! Manually remove from the shared task treebanks that we do not want there although they are valid.
    my @stpresel = qw(UD_Afrikaans-AfriBooms UD_Ancient_Greek-PROIEL UD_Ancient_Greek-Perseus
    UD_Arabic-PADT UD_Armenian-ArmTDP UD_Basque-BDT UD_Breton-KEB UD_Bulgarian-BTB
    UD_Buryat-BDT UD_Catalan-AnCora UD_Chinese-GSD UD_Croatian-SET
    UD_Czech-CAC UD_Czech-FicTree UD_Czech-PDT UD_Czech-PUD UD_Danish-DDT
    UD_Dutch-Alpino UD_Dutch-LassySmall
    UD_English-EWT UD_English-GUM UD_English-LinES UD_English-PUD UD_Estonian-EDT
    UD_Faroese-OFT UD_Finnish-FTB UD_Finnish-PUD UD_Finnish-TDT
    UD_French-GSD UD_French-Sequoia UD_French-Spoken UD_Galician-CTG UD_Galician-TreeGal
    UD_German-GSD UD_Gothic-PROIEL UD_Greek-GDT UD_Hebrew-HTB UD_Hindi-HDTB
    UD_Hungarian-Szeged UD_Indonesian-GSD UD_Irish-IDT UD_Italian-ISDT UD_Italian-PoSTWITA
    UD_Japanese-GSD UD_Japanese-Modern UD_Kazakh-KTB UD_Korean-GSD UD_Korean-Kaist
    UD_Kurmanji-MG UD_Latin-ITTB UD_Latin-PROIEL UD_Latin-Perseus UD_Latvian-LVTB
    UD_Naija-NSC UD_North_Sami-Giella
    UD_Norwegian-Bokmaal UD_Norwegian-Nynorsk UD_Norwegian-NynorskLIA
    UD_Old_Church_Slavonic-PROIEL UD_Old_French-SRCMF UD_Persian-Seraji
    UD_Polish-LFG UD_Polish-SZ UD_Portuguese-Bosque UD_Romanian-RRT
    UD_Russian-SynTagRus UD_Russian-Taiga UD_Serbian-SET UD_Slovak-SNK
    UD_Slovenian-SSJ UD_Slovenian-SST UD_Spanish-AnCora
    UD_Swedish-LinES UD_Swedish-PUD UD_Swedish-Talbanken UD_Thai-PUD UD_Turkish-IMST
    UD_Ukrainian-IU UD_Upper_Sorbian-UFAL UD_Urdu-UDTB UD_Uyghur-UDT UD_Vietnamese-VTB);
    my $stpresel = join('|', @stpresel);
    if($folder =~ m/^UD_(Russian-GSD|Spanish-GSD|Turkish-PUD)$/)
    {
        $stmessage = 'not in shared task: intra-language inconsistency';
    }
    elsif($stmessage eq '' && $folder !~ m/^($stpresel)$/)
    {
        $stmessage = 'not in shared task: not ready in time';
    }
    $treebank_message = $folder_success ? "$folder: VALID" : "$folder: ERROR";
    if($folder_success && $stmessage ne '')
    {
        $treebank_message .= " ($stmessage)";
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
    if($n==0)
    {
        if($section eq 'any')
        {
            print STDERR ("WARNING: No data found in '$path/$udfolder'\n");
        }
        else
        {
            print STDERR ("WARNING: No $section data found in '$path/$udfolder'\n");
        }
    }
    else
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
