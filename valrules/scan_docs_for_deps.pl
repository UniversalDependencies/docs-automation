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

# Describe banned relations. People sometimes define a language-specific subtype
# for something that is already defined for many other languages but with a
# different label! This goes against the spirit of UD and it should be suppressed.
# The regular expressions below describe the entire "type:subtype" string. They
# will be matched with ^ and $ at the ends, case-insensitively.
my @deviations =
(
    {'re'  => 'acl:rel',
     'msg' => "The recommended label for relative clauses is 'acl:relcl'."}
);

# The docs repository should be locatable relatively to this script:
# this script = .../docs-automation/valrules/scan_docs_for_feats.pl
# docs        = .../docs
# Temporarily go to the folder of the script (if we are not already there).
my $currentpath = getcwd();
my $scriptpath = $0;
if($scriptpath =~ m:/:)
{
    $scriptpath =~ s:/[^/]*$:/:;
    chdir($scriptpath) or die("Cannot go to folder '$scriptpath': $!");
}
# Go to docs relatively to the script position.
chdir('../../docs') or die("Cannot go from ".getcwd()." to folder '../../docs': $!");
my $docs = getcwd();
chdir($currentpath);
# We are back in the original folder and we have the absolute path to docs.
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
                $lhash{$lcode}{$relation}{type} = 'global';
            }
        }
        else
        {
            push(@{$lhash{$lcode}{$relation}{errors}}, "Relation '$relation' is not a subtype of any approved main type.");
        }
        read_relation_doc($relation, "$lddeps/$file", $lhash{$lcode}{$relation}, \@deviations);
    }
}
# Print an overview of the features we found.
print_markdown_overview(\%hash, \%lhash);
#print_json(\%hash, \%lhash, \@deviations, $docs);



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
        # Check whether examples are given for each relation.
        if(m/^~~~\s*(sdparse|conllu)\s*$/)
        {
            $dephash{examples}++;
        }
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
# Prints an overview of all documented relations (as well as errors in the
# format of documentation), formatted using MarkDown syntax.
#------------------------------------------------------------------------------
sub print_markdown_overview
{
    my $ghash = shift; # ref to hash with global features
    my $lhash = shift; # ref to hash with local features
    my @relations = sort(keys(%{$ghash}));
    print("# Universal relations\n\n");
    foreach my $relation (grep {$ghash->{$_}{type} eq 'universal'} (@relations))
    {
        my $file = $relation;
        $file = 'aux_' if($file eq 'aux');
        print("* [$relation](https://universaldependencies.org/u/dep/$file.html)\n");
        foreach my $error (@{$ghash->{$relation}{errors}})
        {
            print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
        }
    }
    print("\n");
    print("# Globally documented non-universal relations\n\n");
    foreach my $relation (grep {$ghash->{$_}{type} eq 'global'} (@relations))
    {
        my $file = $relation;
        $file =~ s/^([a-z]+):([a-z]+)$/$1-$2/;
        print("* [$relation](https://universaldependencies.org/u/dep/$file.html)\n");
        foreach my $error (@{$ghash->{$relation}{errors}})
        {
            print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
        }
    }
    print("\n");
    print("# Locally documented language-specific relations\n\n");
    my @lcodes = sort(keys(%{$lhash}));
    my $n = scalar(@lcodes);
    print("The following $n languages seem to have at least some documentation of relations: ".join(' ', map {"$_ (".scalar(keys(%{$lhash->{$_}})).")"} (@lcodes))."\n");
    print("\n");
    foreach my $lcode (@lcodes)
    {
        print("## $lcode\n\n");
        my @relations = sort(keys(%{$lhash->{$lcode}}));
        foreach my $relation (@relations)
        {
            my $file = $relation;
            $file =~ s/^([a-z]+):([a-z]+)$/$1-$2/;
            print("* [$relation](https://universaldependencies.org/$lcode/dep/$file.html)\n");
            foreach my $error (@{$lhash->{$lcode}{$relation}{errors}})
            {
                print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
            }
        }
        print("\n");
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
    # We need to know the list of all UD languages first.
    my $docspath = shift;
    my $languagespath = "$docspath/../docs-automation/codes_and_flags.yaml";
    my $languages = LoadFile($languagespath);
    if( !defined($languages) )
    {
        die "Cannot read the list of languages";
    }
    my @lcodes = sort(map {$languages->{$_}{lcode}} (keys(%{$languages})));
    print("{\n");
    print("\"lists\": {\n");
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
        push(@jsonlines, '"'.escape_json_string($lcode).'": ['.join(', ', map {'"'.escape_json_string($_).'"'} (@relations)).']');
    }
    print(join(",\n", @jsonlines)."\n");
    print("},\n"); # end of lists
    print("\"gdocs\": {\n");
    my @relationlines = ();
    foreach my $relation (sort(keys(%{$ghash})))
    {
        push(@relationlines, '"'.escape_json_string($relation).'": '.encode_relation_json($ghash->{$relation}));
    }
    print(join(",\n", @relationlines)."\n");
    print("},\n"); # end of gdocs
    print("\"ldocs\": {\n");
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
                push(@relationlines, '"'.escape_json_string($relation).'": '.encode_feature_json($lhash->{$lcode}{$relation}));
            }
            $languageline .= join(",\n", @relationlines)."\n";
            $languageline .= '}';
            push(@languagelines, $languageline);
        }
    }
    print(join(",\n", @languagelines)."\n");
    print("},\n"); # end of ldocs
    print("\"deviations\": [\n");
    my @deviationlines = ();
    foreach my $d (@{$deviations})
    {
        push(@deviationlines, encode_json(['re' => $d->{re}], ['msg' => $d->{msg}]));
    }
    print(join(",\n", @deviationlines)."\n");
    print("]\n"); # end of deviations
    print("}\n");
}



#------------------------------------------------------------------------------
# Encodes the hash of one feature in JSON.
#------------------------------------------------------------------------------
sub encode_relation_json
{
    my $relation = shift; # hash reference
    my $json = '{';
    $json .= '"type": "'.escape_json_string($relation->{type}).'", ';
    $json .= '"errors": ['.join(', ', map {'"'.escape_json_string($_).'"'} (@{$relation->{errors}})).']';
    $json .= '}';
    return $json;
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
                die("Unknown value of attribute '$name'");
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
