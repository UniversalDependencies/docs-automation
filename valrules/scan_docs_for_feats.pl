#!/usr/bin/env perl
# Scans the UD docs repository for documentation of features.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# At present, the path to the local copy of docs is hardwired.
my $docs = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies/docs';
my %hash;
my %lhash;
# Scan globally documented features.
# Some of them are officially part of the universal guidelines.
# The rest are technically language-specific but individual languages do not have to document them individually.
my @ufeats = qw(Abbr Animacy Aspect Case Clusivity Definite Degree Evident Foreign Gender Mood NounClass Number NumType Person Polarity Polite Poss PronType Reflex Tense Typo VerbForm Voice);
my $gdfeats = "$docs/_u-feat";
opendir(DIR, $gdfeats) or die("Cannot read folder '$gdfeats': $!");
my @gdfiles = grep {m/^.+\.md$/ && -f "$gdfeats/$_"} (readdir(DIR));
closedir(DIR);
foreach my $file (@gdfiles)
{
    my $feature = $file;
    $feature =~ s/\.md$//;
    if(grep {$_ eq $feature} (@ufeats))
    {
        $hash{$feature}{type} = 'universal';
    }
    else
    {
        $hash{$feature}{type} = 'global';
    }
    if($feature !~ m/^[A-Z][A-Za-z0-9]*$/)
    {
        push(@{$hash{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
    }
    read_feature_doc("$gdfeats/$file", \%{$hash{$feature}});
}
# Scan locally documented (language-specific) features.
opendir(DIR, $docs) or die("Cannot read folder '$docs': $!");
my @langfolders = sort(grep {m/^_[a-z]{2,3}$/ && -d "$docs/$_/feat"} (readdir(DIR)));
closedir(DIR);
foreach my $langfolder (@langfolders)
{
    my $lcode = $langfolder;
    $lcode =~ s/^_//;
    my $ldfeats = "$docs/$langfolder/feat";
    opendir(DIR, $ldfeats) or die("Cannot read folder '$ldfeats': $!");
    my @ldfiles = grep {m/^.+\.md$/ && -f "$ldfeats/$_"} (readdir(DIR));
    closedir(DIR);
    foreach my $file (@ldfiles)
    {
        my $feature = $file;
        $feature =~ s/\.md$//;
        if(grep {$_ eq $feature} (@ufeats))
        {
            $lhash{$lcode}{$feature}{type} = 'universal';
        }
        else
        {
            $lhash{$lcode}{$feature}{type} = 'local';
        }
        if($feature !~ m/^[A-Z][A-Za-z0-9]*$/)
        {
            push(@{$lhash{$lcode}{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
        }
        read_feature_doc("$ldfeats/$file", $lhash{$lcode}{$feature});
    }
}
# Print an overview of the features we found.
my @features = sort(keys(%hash));
print("# Universal features\n\n");
foreach my $feature (grep {$hash{$_}{type} eq 'universal'} (@features))
{
    print("* [$feature](https://universaldependencies.org/u/feat/$feature.html)\n");
    foreach my $value (@{$hash{$feature}{values}})
    {
        print('  * value `'.$value.'`: '.$hash{$feature}{valdoc}{$value}{shortdesc}."\n");
    }
    foreach my $error (@{$hash{$feature}{errors}})
    {
        print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
    }
}
print("\n");
print("# Globally documented non-universal features\n\n");
foreach my $feature (grep {$hash{$_}{type} eq 'global'} (@features))
{
    print("* [$feature](https://universaldependencies.org/u/feat/$feature.html)\n");
    foreach my $value (@{$hash{$feature}{values}})
    {
        print('  * value `'.$value.'`: '.$hash{$feature}{valdoc}{$value}{shortdesc}."\n");
    }
    foreach my $error (@{$hash{$feature}{errors}})
    {
        print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
    }
}
print("\n");
print("# Locally documented language-specific features\n\n");
my @lcodes = sort(keys(%lhash));
my $n = scalar(@lcodes);
print("The following $n languages seem to have at least some documentation of features: ".join(' ', map {"$_ (".scalar(keys(%{$lhash{$_}})).")"} (@lcodes))."\n");
print("\n");
foreach my $lcode (@lcodes)
{
    print("## $lcode\n\n");
    my @features = sort(keys(%{$lhash{$lcode}}));
    foreach my $feature (@features)
    {
        print("* [$feature](https://universaldependencies.org/$lcode/feat/$feature.html)\n");
        foreach my $value (@{$lhash{$lcode}{$feature}{values}})
        {
            print('  * value `'.$value.'`: '.$lhash{$lcode}{$feature}{valdoc}{$value}{shortdesc}."\n");
        }
        foreach my $error (@{$lhash{$lcode}{$feature}{errors}})
        {
            print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
        }
    }
    print("\n");
}



#------------------------------------------------------------------------------
# Reads a MarkDown file that documents one feature.
#------------------------------------------------------------------------------
sub read_feature_doc
{
    my $filepath = shift;
    my $feathash = shift; # hash reference
    my $udver = 1;
    my @values = ();
    my %valdoc;
    my $current_value;
    my @unrecognized_example_lines;
    #print STDERR ("Reading $filepath\n");
    open(FILE, $filepath) or die("Cannot read file '$filepath': $!");
    while(<FILE>)
    {
        chomp();
        s/\s+$//;
        # The following line should occur in the MarkDown header (between two '---' lines).
        # We take the risk and do not check where exactly it occurs.
        if(m/^udver:\s*'(\d+)'$/)
        {
            $udver = $1;
        }
        # Feature values will be recognized only if they have a section heading in the prescribed form.
        if(m/^\#\#\#\s*<a\s+name="(.+?)"\s*>`\1`<\/a>:\s*(.+)$/)
        {
            my $value = $1;
            my $short_description = $2;
            if(defined($current_value) && $valdoc{$current_value}{examples} == 0)
            {
                push(@{$feathash->{errors}}, "No examples found under value '$current_value'.", @unrecognized_example_lines);
            }
            if(exists($valdoc{$value}))
            {
                push(@{$feathash->{errors}}, "Multiple definition of value '$value'.");
            }
            else
            {
                $current_value = $value;
                @unrecognized_example_lines = ();
                push(@values, $value);
                $valdoc{$value}{shortdesc} = $short_description;
            }
            if($value !~ m/^[A-Z0-9][A-Za-z0-9]*$/)
            {
                push(@{$feathash->{errors}}, "Feature value '$value' does not have the prescribed form.");
            }
        }
        # Warn about unrecognized level 3 headings.
        # Note that there are some examples of legitimate level 3 headings that are not feature values.
        # References is one such case. The "Prague Dependency Treebank" exception is needed if there is a Diff section (level 2) with treebanks that currently differ from the overall guidelines.
        elsif(m/^\#\#\#[^\#]/ && !m/^\#\#\#\s*(References|Prague Dependency Treebank)$/)
        {
            push(@{$feathash->{errors}}, "Unrecognized level 3 heading '$_'.");
        }
        # Check whether examples are given for each value.
        if(m/^(\#\#\#\#\s*)?Examples?:?/)
        {
            if(defined($current_value))
            {
                $valdoc{$current_value}{examples}++;
            }
        }
        elsif(m/examples/i)
        {
            # We will report this as an error only if we have not found an actual Examples heading.
            push(@unrecognized_example_lines, "Unrecognized examples '$_'.");
        }
    }
    close(FILE);
    if(defined($current_value) && $valdoc{$current_value}{examples} == 0)
    {
        push(@{$feathash->{errors}}, "No examples found under value '$current_value'.", @unrecognized_example_lines);
    }
    if($udver != 2)
    {
        push(@{$feathash->{errors}}, "Documentation does not belong to UD v2 guidelines.");
    }
    if(scalar(@values)==0)
    {
        push(@{$feathash->{errors}}, "No feature values found.");
    }
    $feathash->{values} = \@values;
    $feathash->{valdoc} = \%valdoc;
}
