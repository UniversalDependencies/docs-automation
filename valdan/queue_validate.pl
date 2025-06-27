#!/usr/bin/env perl
# An envelope around update-validation-report.pl. It checks a file with queued
# validation requests, adds new requests if they are not already there, starts
# processing the requests if no other process is already doing so, and proceeds
# until the queue is empty.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

sub usage
{
    print STDERR ("Usage: $0 UD_Xxx-XTB [UD_Yyy-YTB UD_Zzz-ZTB ...]\n");
}

# Add my treebanks to the queue.
my @q = read_queue();
printf STDERR ("There were %d items in the queue.\n", scalar(@q));
printf STDERR ("I have %d items to add if they are not already there.\n", scalar(@ARGV));
my %qmap;
foreach my $item (@q)
{
    # $item->[0] ... treebank name
    # $item->[1] ... timestamp added to queue
    # $item->[2] ... timestamp started validating
    # $item->[3] ... pid of process doing validation
    $qmap{$item->[0]} = $item;
}
my $timestamp = time();
foreach my $treebank (@ARGV)
{
    if($treebank =~ m/^UD_/)
    {
        if(exists($qmap{$treebank}))
        {
            # If the treebank is in the queue but its validation already runs,
            # add it to the queue again.
            if($qmap{$treebank}[2])
            {
                push(@q, [$treebank, $timestamp]);
                $qmap{$treebank} = $q[-1];
            }
        }
        else
        {
            push(@q, [$treebank, $timestamp]);
            $qmap{$treebank} = $q[-1];
        }
    }
}
printf STDERR ("There are %d items after considering the new ones.\n", scalar(@q));
write_queue(@q);
# Now check whether one or more items in the queue are already being processed.
my $n_processed = 0;
foreach my $item (@q)
{
    if($item->[2])
    {
        print STDERR ("%s is being processed by pid %d since %d seconds ago.\n", $item->[0], $item->[3], $timestamp-$item->[2]);
        $n_processed++;
        ###!!! Risk: The other process may have crashed. We should verify that
        ###!!! it is still running. And maybe also that the processing of the
        ###!!! current treebank does not take too long – even the largest tree-
        ###!!! banks should not require more than 30 minutes.
    }
}
if($n_processed)
{
    print STDERR ("Leaving the queue for the other workers to finish, terminating.");
    exit(0);
}
# If nobody is currently processing the queue, we have to do it.
print STDERR ("No other process is working on the queue, I am going to do it (pid=$$).\n");
while(scalar(@q))
{
    printf STDERR ("%d treebanks in the queue, picking %s\n", scalar(@q), $q[0][0]);
    $timestamp = time();
    $q[0][2] = $timestamp;
    $q[0][3] = $$;
    write_queue(@q);
    my $current_treebank = $q[0][0];
    system("perl ./update-validation-report.pl $current_treebank");
    @q = read_queue();
    # The first item in the queue should be the job we just finished, but let's
    # not rely on it – someone may have corrupted the queue in the meantime.
    @q = grep {!($_->[0] eq $current_treebank && $_->[3] == $$)} (@q);
    write_queue(@q);
}



#------------------------------------------------------------------------------
# Reads the current queue, if any.
#------------------------------------------------------------------------------
sub read_queue
{
    my $queue_file = './queue.txt';
    my @queue = ();
    open(QUEUE, $queue_file) or return;
    while(<QUEUE>)
    {
        s/\r?\n$//;
        # The queue contains one line per UD treebank, the line has TAB-separated fields.
        # The first field is the name of the treebank. It starts with 'UD'.
        next unless(m/^UD_/);
        my @f = split(/\t/, $_);
        push(@queue, \@f);
    }
    close(QUEUE);
    return @queue;
}



#------------------------------------------------------------------------------
# Writes the queue from memory, overwrites whatever is on the disk.
#------------------------------------------------------------------------------
sub write_queue
{
    my $queue_file = './queue.txt';
    my @queue = @_;
    open(QUEUE, ">$queue_file") or die("Cannot write '$queue_file': $!");
    foreach my $f (@queue)
    {
        print QUEUE (join("\t", @{$f}), "\n");
    }
    close(QUEUE);
}
