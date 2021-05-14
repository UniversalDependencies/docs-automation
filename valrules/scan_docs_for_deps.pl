#!/usr/bin/env perl
# Scans the UD docs repository for documentation of features.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Cwd; # getcwd()
use YAML qw(LoadFile);
# We need to tell Perl where to find my Perl modules, relative to the location
# of the script. We will also need the path to access the data.
my ($currentpath, $scriptpath, $docs);
BEGIN
{
    $currentpath = getcwd();
    $scriptpath = $0;
    $scriptpath =~ s:\\:/:g;
    if($scriptpath =~ m:/:)
    {
        $scriptpath =~ s:/[^/]*$:/:;
        chdir($scriptpath) or die("Cannot go to folder '$scriptpath': $!");
    }
    $scriptpath = getcwd();
    # Go to docs relatively to the script position.
    chdir('../../docs') or die("Cannot go from $scriptpath to folder '../../docs': $!");
    $docs = getcwd();
    chdir($currentpath);
}
use lib $scriptpath;
use valdata;

# Describe banned relations. People sometimes define a language-specific subtype
# for something that is already defined for many other languages but with a
# different label! This goes against the spirit of UD and it should be suppressed.
# The regular expressions below describe the entire "type:subtype" string. They
# will be matched with ^ and $ at the ends, case-insensitively.
my @deviations =
(
    {'re'  => 'acl:rel',
     'msg' => "The recommended label for relative clauses is 'acl:relcl'."},
    {'re'  => 'obl:loc',
     'msg' => "The recommended label for locative oblique nominals is 'obl:lmod'."}
);

my %hash;
my %lhash;
# Scan globally documented relations.
# The list of main types defined in the guidelines is hardcoded here.
# Subtypes are all technically language-specific but some of them are de-facto
# standard because they are used in many languages or even mentioned in the
# official guidelines. Those that are documented globally do not have to be
# also documented for individual languages (although they can).
my @udeps = qw(nsubj csubj obj iobj ccomp xcomp obl advmod advcl
               expl dislocated vocative discourse aux cop
               det clf nummod amod nmod acl 21
               case mark cc conj appos compound flat fixed parataxis 30
               goeswith reparandum orphan list punct root dep);
my $gddeps = "$docs/_u-dep";
opendir(DIR, $gddeps) or die("Cannot read folder '$gddeps': $!");
my @gdfiles = grep {m/^.+\.md$/ && -f "$gddeps/$_"} (readdir(DIR));
closedir(DIR);
foreach my $file (@gdfiles)
{
    my $relation = $file;
    $relation =~ s/\.md$//;
    # If the relation is 'aux', the file must be named 'aux_.md' instead of 'aux.md'
    # so that the file can exist in any operating system, including Microsoft Windows.
    if($relation eq 'aux')
    {
        push(@{$hash{$relation}{errors}}, "File must not be named 'aux.md' (portability across systems). Use 'aux_.md' instead.");
    }
    elsif($relation eq 'aux_')
    {
        $relation = 'aux';
    }
    # Check whether this is a subtype and if it is, whether the first part is a known universal dependency relation.
    # Subtypes have colon ':' in the name but the file name uses a hyphen instead.
    my $udep = $relation;
    my $sdep = '';
    if($relation =~ s/^([a-z]+)-([a-z]+)$/$1:$2/)
    {
        $udep = $1;
        $sdep = $2;
    }
    if($relation !~ m/^[a-z]+(:[a-z]+)?$/)
    {
        push(@{$hash{$relation}{errors}}, "Relation '$relation' does not have the prescribed form.");
    }
    if(grep {$_ eq $udep} (@udeps))
    {
        if($sdep eq '')
        {
            $hash{$relation}{type} = 'universal';
        }
        else
        {
            $hash{$relation}{type} = 'global';
        }
    }
    else
    {
        push(@{$hash{$relation}{errors}}, "Relation '$relation' is not a subtype of any approved main type.");
    }
    read_relation_doc($relation, "$gddeps/$file", $hash{$relation}, \@deviations);
}
# Scan locally documented (language-specific) features.
opendir(DIR, $docs) or die("Cannot read folder '$docs': $!");
my @langfolders = sort(grep {m/^_[a-z]{2,3}$/ && -d "$docs/$_/dep"} (readdir(DIR)));
closedir(DIR);
foreach my $langfolder (@langfolders)
{
    my $lcode = $langfolder;
    $lcode =~ s/^_//;
    my $lddeps = "$docs/$langfolder/dep";
    opendir(DIR, $lddeps) or die("Cannot read folder '$lddeps': $!");
    my @ldfiles = grep {m/^.+\.md$/ && -f "$lddeps/$_"} (readdir(DIR));
    closedir(DIR);
    foreach my $file (@ldfiles)
    {
        my $relation = $file;
        $relation =~ s/\.md$//;
        # If the relation is 'aux', the file must be named 'aux_.md' instead of 'aux.md'
        # so that the file can exist in any operating system, including Microsoft Windows.
        if($relation eq 'aux')
        {
            push(@{$lhash{$lcode}{$relation}{errors}}, "File must not be named 'aux.md' (portability across systems). Use 'aux_.md' instead.");
        }
        elsif($relation eq 'aux_')
        {
            $relation = 'aux';
        }
        # Check whether this is a subtype and if it is, whether the first part is a known universal dependency relation.
        # Subtypes have colon ':' in the name but the file name uses a hyphen instead.
        my $udep = $relation;
        my $sdep = '';
        if($relation =~ s/^([a-z]+)-([a-z]+)$/$1:$2/)
        {
            $udep = $1;
            $sdep = $2;
        }
        if($relation !~ m/^[a-z]+(:[a-z]+)?$/)
        {
            push(@{$lhash{$lcode}{$relation}{errors}}, "Relation '$relation' does not have the prescribed form.");
        }
        if(grep {$_ eq $udep} (@udeps))
        {
            if($sdep eq '')
            {
                $lhash{$lcode}{$relation}{type} = 'universal';
            }
            else
            {
                $lhash{$lcode}{$relation}{type} = 'local';
            }
        }
        else
        {
            push(@{$lhash{$lcode}{$relation}{errors}}, "Relation '$relation' is not a subtype of any approved main type.");
        }
        read_relation_doc($relation, "$lddeps/$file", $lhash{$lcode}{$relation}, \@deviations);
    }
}
# Print an overview of the relations we found.
print_json(\%hash, \%lhash, \@deviations, $docs, "$scriptpath/docdeps.json");
# There is now a larger JSON about deprels of individual languages which
# depends on the contents of docdeps.json generated here.
# The following reader will also read the file docdeps.json we just wrote,
# and project it to the larger data structure. We thus only need to write the
# structure again to update its representation on the disk.
my $data = valdata::read_deprels_json($scriptpath);
valdata::write_deprels_json($data, "$scriptpath/deprels.json");



#------------------------------------------------------------------------------
# Reads a MarkDown file that documents one feature.
#------------------------------------------------------------------------------
sub read_relation_doc
{
    my $relation = shift; # the name of the relation
    my $filepath = shift; # the name and path to the corresponding file
    my $dephash = shift; # hash reference
    my $deviations = shift; # array reference
    foreach my $d (@{$deviations})
    {
        if($relation =~ m/^$d->{re}$/i)
        {
            push(@{$dephash->{errors}}, "Wrong relation '$relation'. $d->{msg}");
        }
    }
    my $udver = 1;
    $dephash{examples} = 0;
    my $first_line = 1;
    #print STDERR ("Reading $filepath\n");
    open(FILE, $filepath) or die("Cannot read file '$filepath': $!");
    while(<FILE>)
    {
        chomp();
        s/\s+$//;
        # The first line must consist of three hyphens. Otherwise the file will
        # not be recognized by Jekyll as a MarkDown file and the corresponding
        # HTML page will not be generated. Specifically, the file must not start
        # with an endian signature (\x{FEFF} ZERO WIDTH NO-BREAK SPACE, or the
        # non-character \x{FFFE}).
        if($first_line && !m/^---/)
        {
            push(@{$feathash->{errors}}, "MarkDown page does not start with the required header.");
            if(m/^(\x{FEFF}|\x{FFFE})/)
            {
                push(@{$feathash->{errors}}, "MarkDown page must not start with an endian signature.");
            }
        }
        # The following line should occur in the MarkDown header (between two '---' lines).
        # We take the risk and do not check where exactly it occurs.
        if(m/^udver:\s*'(\d+)'$/)
        {
            $udver = $1;
        }
        # Check whether examples are given for each relation.
        if(m/^~~~\s*(sdparse|conllu)\s*$/)
        {
            $dephash{examples}++;
        }
        $first_line = 0;
    }
    close(FILE);
    if($dephash{examples} == 0)
    {
        push(@{$dephash->{errors}}, "No examples found for relation '$relation'.");
    }
    if($udver != 2)
    {
        push(@{$dephash->{errors}}, "Documentation does not belong to UD v2 guidelines.");
    }
}



#------------------------------------------------------------------------------
# Prints a JSON structure with documented relation types for each UD language.
#------------------------------------------------------------------------------
sub print_json
{
    my $ghash = shift; # ref to hash with global features
    my $lhash = shift; # ref to hash with local features
    my $deviations = shift; # ref to array with banned deviations
    my $docspath = shift; # needed to be able to find the list of all UD languages
    my $filename = shift; # where to write JSON to
    my $languagespath = "$docspath/../docs-automation/codes_and_flags.yaml";
    my $languages = LoadFile($languagespath);
    if( !defined($languages) )
    {
        die "Cannot read the list of languages";
    }
    my @lcodes = sort(map {$languages->{$_}{lcode}} (keys(%{$languages})));
    my $json = '';
    $json .= "{\n";
    $json .= "\"lists\": {\n";
    my @jsonlines = ();
    foreach my $lcode (@lcodes)
    {
        my @relations = ();
        # Add locally defined (or redefined) relations.
        if(exists($lhash->{$lcode}))
        {
            foreach my $relation (sort(keys(%{$lhash->{$lcode}})))
            {
                # Skip the relation if there are errors in its documentation.
                unless(scalar(@{$lhash->{$lcode}{$relation}{errors}}) > 0)
                {
                    push(@relations, $relation);
                }
            }
        }
        # Add globally defined features that are not redefined locally.
        foreach my $relation (sort(keys(%{$ghash})))
        {
            unless(exists($lhash->{$lcode}{$relation}))
            {
                # Skip the relation if there are errors in its documentation.
                unless(scalar(@{$ghash->{$relation}{errors}}) > 0)
                {
                    push(@relations, $relation);
                }
            }
        }
        push(@jsonlines, '"'.valdata::escape_json_string($lcode).'": ['.join(', ', map {'"'.valdata::escape_json_string($_).'"'} (@relations)).']');
    }
    $json .= join(",\n", @jsonlines)."\n";
    $json .= "},\n"; # end of lists
    $json .= "\"gdocs\": {\n";
    my @relationlines = ();
    foreach my $relation (sort(keys(%{$ghash})))
    {
        push(@relationlines, '"'.valdata::escape_json_string($relation).'": '.encode_relation_json($ghash->{$relation}));
    }
    $json .= join(",\n", @relationlines)."\n";
    $json .= "},\n"; # end of gdocs
    $json .= "\"ldocs\": {\n";
    my @languagelines = ();
    foreach my $lcode (sort(keys(%{$lhash})))
    {
        my @relations = sort(keys(%{$lhash->{$lcode}}));
        if(scalar(@relations) > 0)
        {
            my $languageline = "\"$lcode\": {\n";
            @relationlines = ();
            foreach my $relation (@relations)
            {
                push(@relationlines, '"'.valdata::escape_json_string($relation).'": '.encode_relation_json($lhash->{$lcode}{$relation}));
            }
            $languageline .= join(",\n", @relationlines)."\n";
            $languageline .= '}';
            push(@languagelines, $languageline);
        }
    }
    $json .= join(",\n", @languagelines)."\n";
    $json .= "},\n"; # end of ldocs
    $json .= "\"deviations\": [\n";
    my @deviationlines = ();
    foreach my $d (@{$deviations})
    {
        push(@deviationlines, valdata::encode_json(['re' => $d->{re}], ['msg' => $d->{msg}]));
    }
    $json .= join(",\n", @deviationlines)."\n";
    $json .= "]\n"; # end of deviations
    $json .= "}\n";
    open(JSON, ">$filename") or confess("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
}



#------------------------------------------------------------------------------
# Encodes the hash of one feature in JSON.
#------------------------------------------------------------------------------
sub encode_relation_json
{
    my $relation = shift; # hash reference
    my $json = '{';
    $json .= '"type": "'.valdata::escape_json_string($relation->{type}).'", ';
    $json .= '"errors": ['.join(', ', map {'"'.valdata::escape_json_string($_).'"'} (@{$relation->{errors}})).']';
    $json .= '}';
    return $json;
}
