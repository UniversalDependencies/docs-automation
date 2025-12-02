#!/usr/bin/env perl
# Updates the validation report line of a particular treebank.
# Copyright © 2018-2021, 2024, 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# This script prints progress report, as well as validation result, to STDERR.
# Besides, it creates a log file for each treebank folder processed, e.g.,
# log/UD_Czech-PUD.log. Finally, it also updates validation.txt, which is the
# overview of most recent validation results for all treebanks.

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use JSON::Parse ('parse_json', 'json_file_to_perl');
use Time::HiRes qw(gettimeofday tv_interval);
# We need to tell Perl where to find our udlib module.
BEGIN
{
    use Cwd;
    my $path = $0;
    $path =~ s:\\:/:g;
    my $currentpath = getcwd();
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
}
# We assume that a copy of this script is invoked that resides above all UD repositories, including tools.
use lib "$libpath/tools";
use udlib;



# Get the hash of UD language names, codes, and families.
my $languages_from_yaml = udlib::get_language_hash();
my $folder = $ARGV[0];
exit if(!defined($folder));
$folder =~ s:/$::;
$folder =~ s:^\./::;
my ($lname, $tname) = udlib::decompose_repo_name($folder);
my $lcode = $languages_from_yaml->{$lname}{lcode};
# Get the list of previous releases. If the treebank is invalid but there was
# a valid version in the previous release, we can use it as a backup.
my $relfile;
if(-f 'releases.json')
{
    $relfile = 'releases.json';
}
else
{
    $relfile = "$libpath/docs-automation/valdan/releases.json";
}
my $treebank_history = udlib::get_treebank_history($relfile);
# Get the list of validation dispensations for this treebank.
my $dispfile;
if(-f 'dispensations.json')
{
    $dispfile = 'dispensations.json';
}
else
{
    $dispfile = "$libpath/docs-automation/valdan/dispensations.json";
}
my $dispensations = json_file_to_perl($dispfile)->{dispensations};
# We had >/dev/null 2>&1 here, to make the log more compact and nicer. But then
# we unfortunately did not see what happened when the repo did not get updated.
# Note that this script is typically called from githook.pl and its STDOUT +
# STDERR is saved in log/validation.log.
#system("cd $folder ; (git pull --no-edit >/dev/null 2>&1) ; cd ..");
system("cd $folder ; git pull --no-edit ; cd ..");
system("echo `date` $folder START >&2");
my $start_time = [gettimeofday];
my @files = get_conllu_file_list($folder);
my $folder_empty = scalar(@files) == 0;
my $folder_success = 1;
my %error_stats;
if(!$folder_empty)
{
    system("date > log/$folder.log 2>&1");
    # Check list of files and metadata in README.
    my $command = "tools/check_files.pl $folder";
    print STDERR ("$command\n");
    system("echo $command >> log/$folder.log");
    my $result = saferun("perl -I perllib/lib/perl5 -I perllib/lib/perl5/x86_64-linux-gnu-thread-multi $command >> log/$folder.log 2>&1");
    $folder_success = $folder_success && $result;
    # Check individual data files. Check them all in one validator run.
    my $files = join(' ', map {"$folder/$_"} (@files));
    $command = "./validate.sh --lang $lcode --max-err 0 $files";
    print STDERR ("$command\n");
    system("echo $command >> log/$folder.log");
    $result = saferun("$command >> log/$folder.log 2>&1");
    $folder_success = $folder_success && $result;
    count_error_types("log/$folder.log", \%error_stats);
    # Make sure that the success flag corresponds to what we consider success in the error statistics.
    $folder_success = compare_folder_success_with_error_stats($folder_success, \%error_stats);
    # From now on, we can focus on %error_stats and forget $folder_success (i.e., updating it on the previous line was not really necessary).
}
# Convert the hash of error types to the list of quadruples [$level, $class, $testid, $count].
# The first two elements are always totals of errors and warnings, respectively.
my @error_types_4 = summarize_error_types(\%error_stats);
my @error_testids = map {$_->[2]} (grep {$_->[0] ne 'TOTAL' && $_->[1] ne 'WARNING'} (@error_types_4));
my @warning_testids = map {$_->[2]} (grep {$_->[0] ne 'TOTAL' && $_->[1] eq 'WARNING'} (@error_types_4));
my $n_error_types = scalar(@error_testids);
my $n_warning_types = scalar(@warning_testids);
# If there are errors, the following function will print to STDERR their forgivable / unforgivable status.
my ($unforgivable, $date_oldest_dispensation) = apply_dispensations($folder, \@error_testids, $dispensations);
my $legacy_status = get_legacy_status($folder, $folder_empty, $n_error_types, $n_warning_types, $treebank_history, $unforgivable, $date_oldest_dispensation);
my @unused = get_unused_exceptions($folder, \@error_testids, $dispensations);
my $treebank_message = get_treebank_message($folder, $legacy_status, \@error_types_4, \@unused);
print STDERR ("$treebank_message\n");
# Log all validation runs with git repository versions in a form in which we can later search them.
my $jsonlog = read_json_log('validation-runs.json');
my $current_run = get_json_log($folder, $legacy_status, \@error_types_4, \@unused);
push(@{$jsonlog}, $current_run);
write_json_log('validation-runs.json', $jsonlog);
system("echo `date` $folder END >&2");
my $elapsed = tv_interval($start_time);  # in seconds, as a float
# Two line breaks after this last line we are sending to STDERR (to make the global log more readable).
printf STDERR ("Elapsed time: %.3f seconds\n\n", $elapsed);
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
# This is still not 100% safe: If two processes try to modify the file at the
# same time, it can get corrupt. However, it is not very likely.
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



#------------------------------------------------------------------------------
# Sanity check: If validation scripts returned success, there can be warnings
# but no errors. If there is a discrepancy, add an internal error to the stats
# and return false.
#------------------------------------------------------------------------------
sub compare_folder_success_with_error_stats
{
    my $folder_success = shift;
    my $error_stats = shift;
    my @error_types = sort(keys(%{$error_stats}));
    my $n_errors = scalar(grep {$_->[1] ne 'WARNING'} (map {my @f = split(/\s+/, $_); \@f} (@error_types)));
    if($folder_success && $n_errors > 0)
    {
        $error_stats->{'LX INTERNAL VALIDATION-SUCCESS-BUT-NONZERO-ERRORS'}++;
        return 0;
    }
    return 1;
}



#------------------------------------------------------------------------------
# Takes the error statistics of a treebank. Counts errors and warnings of
# different types.
#------------------------------------------------------------------------------
sub summarize_error_types
{
    my $error_stats = shift;
    my @error_types = sort(keys(%{$error_stats}));
    # Error types include level, class, and test id, e.g., "L3 Syntax leaf-mark-case".
    # Items of @error_types_4 are quadruples (arrays) where these three things are separate, and followed by the count of the error.
    my @error_types_4 = map {my @f = split(/\s+/, $_); push(@f, $error_stats->{$_}); \@f} (@error_types);
    my $n_errors = 0;
    my $n_warnings = 0;
    foreach my $item (@error_types_4)
    {
        if($item->[1] eq 'WARNING')
        {
            $n_warnings += $item->[3];
        }
        else
        {
            $n_errors += $item->[3];
        }
    }
    unshift(@error_types_4, ['TOTAL', 'WARNING', '', $n_warnings]);
    unshift(@error_types_4, ['TOTAL', 'ERROR',   '', $n_errors]);
    return @error_types_4;
}



#------------------------------------------------------------------------------
# Compares the list of error types with the list of dispensations for the given
# treebank. Prints to STDERR classification of each error as either forgivable
# or unforgivable. Returns the list of unforgivable error types together with
# the date of the oldest dispensation used (so that the caller can verify that
# it has not expired).
# If there are errors, prints to STDERR their forgivable vs. unforgivable
# status.
#------------------------------------------------------------------------------
sub apply_dispensations
{
    my $folder = shift;
    my $error_types = shift; # array ref
    my $dispensations = shift; # hash ref
    my @unforgivable = ();
    my $date_oldest_dispensation;
    foreach my $error_type (@{$error_types})
    {
        if(exists($dispensations->{$error_type}))
        {
            # Some treebanks have dispensations for this error type. Is our treebank among them?
            if(grep {$_ eq $folder} (@{$dispensations->{$error_type}{treebanks}}))
            {
                if(!defined($date_oldest_dispensation) || $dispensations->{$error_type}{date} lt $date_oldest_dispensation)
                {
                    $date_oldest_dispensation = $dispensations->{$error_type}{date};
                }
                print STDERR ("Forgivable exception '$error_type'\n");
            }
            else
            {
                push(@unforgivable, $error_type);
                print STDERR ("Unforgivable error '$error_type'\n");
            }
        }
        else
        {
            push(@unforgivable, $error_type);
            print STDERR ("Unforgivable error '$error_type'\n");
        }
    }
    return (\@unforgivable, $date_oldest_dispensation);
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
    my $empty = shift;
    my $n_error_types = shift;
    my $n_warning_types = shift;
    my $treebank_history = shift; # hash ref
    my $unforgivable = shift; # array ref
    my $date_oldest_dispensation = shift;
    # If this treebank has not yet been released, it is SAPLING. It can be EMPTY, ERROR, or VALID. If VALID, it will be released next time.
    # If this treebank has been released, i.e., it was VALID at some point in time w.r.t. the then used version of the validator:
    # Specifically, if the treebank was included in the most recent release:
    #   It is VALID now. It can be released again.
    #     This includes treebanks for which the validator issues warnings but not real errors.
    #   It is EMPTY now. Strange situation which should not occur.
    #   It is ERROR now.
    #     All types of errors are newly introduced errors that the treebank did not have in the last release: BACKUP.
    #     All types of errors are forgivable, i.e., the treebank has dispensations for them, and they are less than 3 years old: LEGACY.
    #     Some errors are newly introduced and some errors have dispensations less than 3 years old: BACKUP (or explicitly BACKUP+LEGACY?)
    #     Some dispensations are less than 4 but more than 3 years old: NEGLECTED.
    #     Some dispensations are more than 4 years old: INVALID. It will not be released again unless the errors are fixed.
    # If the treebank was not included in the most recent release, it is treated like a SAPLING but maybe it should use a different label so people see it is not new.
    #
    # Hence we have:
    #
    # Novelty: SAPLING (never released) / CURRENT (released last time) / RETIRED (released in the past but not last time)
    # Validity: VALID (no errors) / ERROR (there are errors) / EMPTY (there is no data)
    # Acceptability: VALID (good to go next time) / WARNING (still good to go) / LEGACY (acceptable) / NEGLECTED (last year of acceptability is running) / DISCARD (not acceptable any more) / BACKUP (current data not acceptable but previously released data can be used as a backup)
    # If the treebank has been released, find the number of its last release.
    my $last_release_number;
    my $current = 0;
    if(exists($treebank_history->{$folder}))
    {
        $last_release_number = $treebank_history->{$folder}{lastrel};
        $current = 1 if($last_release_number eq $treebank_history->{relnums}[-1]);
    }
    my $novelty = $current ? 'CURRENT' : defined($last_release_number) ? 'RETIRED' : 'SAPLING';
    my $validity = $empty ? 'EMPTY' : $n_error_types == 0 ? 'VALID' : 'ERROR';
    # The various shades of (in)acceptability are interesting only for current treebanks with errors,
    # for valid treebanks with warnings, or current treebanks that suddenly became empty again.
    my $acceptability;
    if($validity eq 'VALID' && $n_warning_types > 0)
    {
        $acceptability = 'WARNING';
    }
    elsif($current && $validity eq 'EMPTY')
    {
        $acceptability = "BACKUP $last_release_number";
    }
    elsif($current && $n_error_types > 0)
    {
        my @unforgivable = @{$unforgivable};
        # If there are expired dispensations, no backup is possible and unforgivable errors do not matter.
        if(defined($date_oldest_dispensation))
        {
            # We need the time (UTC) when the script is run to identify treebanks that have been neglected for too long.
            my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
            my $today = sprintf("%04d-%02d-%02d", $year+1900, $mon+1, $mday);
            if($date_oldest_dispensation =~ m/^(\d+)-(\d+)-(\d+)$/)
            {
                my $exp1 = ($1+3)."-$2-$3";
                my $exp2 = ($1+4)."-$2-$3";
                if($exp2 lt $today)
                {
                    $acceptability = 'DISCARD';
                }
                elsif(scalar(@unforgivable) > 0)
                {
                    # If we are here, there are new errors that prevent the data from being released.
                    # But there is an older release that could be re-released.
                    ###!!! Backing up to the last release may not solve it. If this is a new
                    ###!!! error type, the previously released data probably have it, too. For
                    ###!!! really new tests in the validator, we will probably add a new
                    ###!!! dispensation and then this treebank will get the legacy status. But
                    ###!!! it is also possible that someone simply disallowed a feature for this
                    ###!!! language. It is not easy to recognize such situation.
                    $acceptability = "BACKUP $last_release_number";
                }
                elsif($exp1 lt $today)
                {
                    $acceptability = "NEGLECTED; $date_oldest_dispensation";
                }
                else
                {
                    $acceptability = "LEGACY; $date_oldest_dispensation";
                }
            }
            else
            {
                # If we are here, the date of the oldest dispensation is in a wrong format.
                $acceptability = "LEGACY; $date_oldest_dispensation";
            }
        }
        elsif(scalar(@unforgivable) > 0)
        {
            # If we are here, there are new errors that prevent the data from being released.
            # But there is an older release that could be re-released.
            ###!!! Backing up to the last release may not solve it. If this is a new
            ###!!! error type, the previously released data probably have it, too. For
            ###!!! really new tests in the validator, we will probably add a new
            ###!!! dispensation and then this treebank will get the legacy status. But
            ###!!! it is also possible that someone simply disallowed a feature for this
            ###!!! language. It is not easy to recognize such situation.
            $acceptability = "BACKUP $last_release_number";
        }
    }
    return defined($acceptability) ? "$novelty $validity $acceptability" : $novelty eq 'RETIRED' ? "$novelty $validity $last_release_number" : "$novelty $validity";
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
    my $dispensations = shift; # hash ref
    my @error_types = @{$error_types};
    my @unused = ();
    foreach my $d (sort(keys(%{$dispensations})))
    {
        foreach my $t (@{$dispensations->{$d}{treebanks}})
        {
            if($t eq $folder)
            {
                unless(grep {$_ eq $d} (@error_types))
                {
                    push(@unused, $d);
                }
                last;
            }
        }
    }
    return @unused;
}



#------------------------------------------------------------------------------
# Generates a treebank status message based on the validation result.
#------------------------------------------------------------------------------
sub get_treebank_message
{
    my $folder = shift;
    my $legacy_status = shift;
    my $error_types_4 = shift;
    my $unused = shift; # array ref
    my $treebank_message = "$folder: $legacy_status";
    # Add the list of errors and warnings to the message.
    # The first two elements in @error_types_4 are always total number of errors and warnings.
    if(scalar(@{$error_types_4}) > 2)
    {
        $treebank_message .= ' ('.join('; ', map {my $x = join(' ', @{$_}); $x =~ s/\s\s+/ /g; $x} (@{$error_types_4})).')';
    }
    # List dispensations that are no longer needed (this can follow any state, VALID or ERROR).
    if(scalar(@{$unused}) > 0)
    {
        $treebank_message .= ' UNEXCEPT '.join(' ', @{$unused});
    }
    return $treebank_message;
}



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
# Gets the last commit information from a git repository. This does not have to
# be the most recent version of that repo; this function is simply used to
# document the version that has been used for a particular action.
#------------------------------------------------------------------------------
sub get_commit_info
{
    my $folder = shift;
    my $commit_id;
    my $author;
    my $timestamp;
    # Ask for the commit time to be converted to the local timezone so that we
    # can compare the timestamps easily.
    my $command = "cd $folder ; (git log --date=iso-local | head -3 2>&1)";
    open(GIT, "$command|") or die("Cannot pipe from '$command': $!");
    while(<GIT>)
    {
        s/\r?\n$//;
        if(m/commit\s+([0-9a-z]+)/)
        {
            $commit_id = $1;
        }
        elsif(m/Author:\s+(.+)/)
        {
            $author = $1;
        }
        elsif(m/Date:\s+(.+)/)
        {
            $timestamp = $1;
            # The format of the output probably depends on the locale and/or on
            # the configuration of git.
        }
    }
    close(GIT);
    if(!defined($commit_id))
    {
        die("Cannot obtain commit information from '$folder'");
    }
    my %record =
    (
        'commit' => $commit_id,
        'author' => $author,
        'timestamp' => $timestamp
    );
    return \%record;
}



#------------------------------------------------------------------------------
# Collects data about the current validation run in the form in which we will
# want to save it in JSON with previous validation runs.
#------------------------------------------------------------------------------
sub get_json_log
{
    my $treebank = shift; # the name of the treebank folder
    # Legacy status is a string of keywords CURRENT VALID / ERROR etc.
    my $legacy_status = shift;
    my $error_types_4 = shift;
    my $unused_dispensations = shift;
    my %cis;
    foreach my $repo ($folder, 'docs', 'docs-automation', 'tools')
    {
        $cis{$repo} = get_commit_info($repo);
    }
    my @lt = localtime(time);
    my $lt = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $lt[5]+1900, $lt[4]+1, $lt[3], $lt[2], $lt[1], $lt[0]);
    my %record =
    (
        'treebank'  => $treebank,
        'message'   => $legacy_status,
        'timestamp' => $lt,
        'errors'    => $error_types_4,
        'version'   => \%cis
    );
    if(scalar(@{$unused_dispensations}) > 0)
    {
        $record{unexcept} = $unused_dispensations;
    }
    return \%record;
}



#------------------------------------------------------------------------------
# Reads JSON-lines log of previous validation runs. Returns it as an array ref.
#------------------------------------------------------------------------------
sub read_json_log
{
    my $filename = shift;
    my @jsonlines;
    open(JSON, $filename) or die("Cannot read '$filename': $!");
    while(<JSON>)
    {
        s/\r?\n$//;
        push(@jsonlines, parse_json($_));
    }
    close(JSON);
    return \@jsonlines;
}



#------------------------------------------------------------------------------
# Write JSON-lines log of previous validation runs plus this one.
#------------------------------------------------------------------------------
sub write_json_log
{
    my $filename = shift;
    my $jsonlog = shift; # array ref
    open(JSON, ">$filename") or die("Cannot write '$filename': $!");
    foreach my $run (@{$jsonlog})
    {
        my @cijsons;
        foreach my $repo ($run->{treebank}, 'docs', 'docs-automation', 'tools')
        {
            my $cijson = '"'.escape_json_string($repo).'": {';
            $cijson .= '"commit": "'.escape_json_string($run->{version}{$repo}{commit}).'", ';
            $cijson .= '"author": "'.escape_json_string($run->{version}{$repo}{author}).'", ';
            $cijson .= '"timestamp": "'.escape_json_string($run->{version}{$repo}{timestamp}).'"';
            $cijson .= '}';
            push(@cijsons, $cijson);
        }
        my @ewjsons;
        foreach my $item (@{$run->{errors}})
        {
            my $ewjson = '['.join(', ', map {'"'.escape_json_string($_).'"'} (@{$item})).']';
            push(@ewjsons, $ewjson);
        }
        my $json = '{"treebank": "'.escape_json_string($run->{treebank}).'", ';
        $json .= '"timestamp": "'.escape_json_string($run->{timestamp}).'", ';
        $json .= '"message": "'.escape_json_string($run->{message}).'", ';
        $json .= '"errors": ['.join(', ', @ewjsons).'], ';
        $json .= '"version": {'.join(', ', @cijsons).'}';
        if(exists($run->{unexcept}) && scalar(@{$run->{unexcept}}) > 0)
        {
            $json .= ', ';
            $json .= '"unexcept": ['.join(', ', map {'"'.escape_json_string($_).'"'} (@{$run->{unexcept}})).']';
        }
        $json .= '}';
        print JSON ("$json\n");
    }
    close(JSON);
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
# The following functions are available in tools/udlib.pm. However, I have
# modified the functions here and they are no longer equivalent to the original
# in udlib.pm.
#==============================================================================



#------------------------------------------------------------------------------
# Scans a UD folder for CoNLL-U files and returns their list.
#------------------------------------------------------------------------------
sub get_conllu_file_list
{
    my $folder = shift;
    my $record = get_ud_files_and_codes($folder);
    # The calling code also needs the language code and the $record has one,
    # guessed from the file names; however, the file names can be wrong, so
    # we will not pass the code up. They will have to obtain the official code
    # from YAML instead.
    return @{$record->{files}};
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
