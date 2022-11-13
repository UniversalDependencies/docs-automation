#!/usr/bin/env perl
# Checks the UD on-line validation report for validation exceptions that are no
# longer needed because the errors of that type have been fixed in the treebank.
# Copyright © 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use LWP::Simple;
use JSON::Parse 'json_file_to_perl';
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

my %unexcept;
# Download the current validation report. (We could run the validator ourselves
# but it would take a lot of time.)
my @validation_report = split(/\n/, get('https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/validation-report.pl?text_only'));
if(scalar(@validation_report)==0)
{
    die("Could not download validation report from quest");
}
foreach my $line (@validation_report)
{
    if($line =~ m/^(UD_.+): .+ UNEXCEPT (.+)/)
    {
        my $folder = $1;
        my @unexcept = split(/\s+/, $2);
        $unexcept{$folder} = \@unexcept;
    }
}
# Read the JSON file.
my $dispensations = json_file_to_perl($jsonfile)->{dispensations};
# Remove dispensations that are no longer needed.
foreach my $d (sort(keys(%{$dispensations})))
{
    my @newlist = ();
    foreach my $t (@{$dispensations->{$d}{treebanks}})
    {
        my $remove = 0;
        if(exists($unexcept{$t}))
        {
            foreach my $e (@{$unexcept{$t}})
            {
                if($e eq $d)
                {
                    $remove = 1;
                    last;
                }
            }
        }
        push(@newlist, $t) unless($remove);
    }
    if(scalar(@newlist) > 0)
    {
        @{$dispensations->{$d}{treebanks}} = @newlist;
    }
    else
    {
        delete($dispensations->{$d});
    }
}
# Write the JSON file.
my $json = "{\n";
$json .= '"dispensations": {'."\n";
@djsons = ();
foreach my $d (sort(keys(%{$dispensations})))
{
    my $date = $dispensations->{$d}{date};
    my $commit = $dispensations->{$d}{commit}; # the first 8 characters of the hash of the corresponding commit to the tools repository
    my $treebanks = $dispensations->{$d}{treebanks};
    my $djson = '"'.$d.'": '.encode_json(['date', $date], ['commit', $commit], ['treebanks', $treebanks, 'list']);
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
