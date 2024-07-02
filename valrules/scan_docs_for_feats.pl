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



# Describe banned features. People sometimes define a language-specific feature
# value for something that is already defined in the guidelines but with a
# different label! This goes against the spirit of UD and it should be suppressed.
# The regular expressions below describe the entire "Feature=Value" pair. They
# will be matched with ^ and $ at the ends, case-insensitively. Do not forget
# that some features may appear with "[layer]".
# For features that are globally documented but not prescribed as universal
# features, the message starts 'Did you mean' rather than 'The correct UD label is'.
my @deviations =
(
    {'re'  => 'Abbr=True',
     'msg' => "The correct UD label for abbreviations is 'Abbr=Yes'."},
    {'re'  => 'Foreign=True',
     'msg' => "The correct UD label for foreign words is 'Foreign=Yes'."},
    {'re'  => 'Typo=True',
     'msg' => "The correct UD label for typos is 'Typo=Yes'."},
    {'re'  => 'Poss=True',
     'msg' => "The correct UD label for possessive pronouns is 'Poss=Yes'."},
    {'re'  => 'Reflex=True',
     'msg' => "The correct UD label for reflexive pronouns is 'Reflex=Yes'."},
    {'re'  => 'NounType=Class(if(ier)?)?',
     'msg' => "Did you mean 'NounType=Clf'?"},
    {'re'  => 'PronType=Inter(r?og(at(ive)?)?)?',
     'msg' => "The correct UD label for interrogative pronouns is 'PronType=Int'."},
    {'re'  => 'PronType=Refl(e?x(ive)?)?',
     'msg' => "The correct UD label for reflexive pronouns is 'PronType=Prs' together with 'Reflex=Yes'."},
    {'re'  => 'PossPerson=.*',
     'msg' => "The correct UD feature for possessor's person is 'Person[psor]'."},
    {'re'  => 'PossNumber=.*',
     'msg' => "The correct UD feature for possessor's number is 'Number[psor]'."},
    {'re'  => '(Degree(ModQpm)?=(Augm(en(t(at(ive)?)?)?)?|Mag)|Augm=Yes)',
     'msg' => "The correct UD label for augmentative is 'Degree=Aug'."},
    {'re'  => '(DegreeModQpm=Dim|(Dim(in(ut(ive)?)?)?)=Yes)',
     'msg' => "The correct UD label for diminutive is 'Degree=Dim'."},
    {'re'  => '(Dem|Distance)=.*',
     'msg' => "Did you mean 'Deixis=Prox|Med|Remt|...'?"},
    {'re'  => 'Deixis=Mid',
     'msg' => "The correct UD label for medial deixis is 'Deixis=Med'?"},
    {'re'  => 'NumForm=Letter',
     'msg' => "Did you mean 'NumForm=Word'?"},
    {'re'  => '(Gender|Animacy|NounClass)(\[[a-z]+\])?=Nonhum',
     'msg' => "The correct UD label for non-human animacy/gender is 'Nhum'."},
    {'re'  => 'Number=Adnum',
     'msg' => "The correct UD label for the special form of noun after numeral is 'Number=Count'."},
    {'re'  => 'Case=(Car(it(ive)?)?)',
     'msg' => "The correct UD label for caritive (abessive) case is 'Case=Abe'."},
    {'re'  => 'Case=(Cmpr|Comp(ar(ative)?)?)',
     'msg' => "The correct UD label for comparative case is 'Case=Cmp'."},
    {'re'  => 'Case=(Ines(s(iv(e)?)?)?)',
     'msg' => "The correct UD label for inessive case is 'Case=Ine'."},
    {'re'  => 'Case=Obl(ique)?',
     'msg' => "The correct UD label for oblique case is 'Case=Acc'."},
    {'re'  => 'Case=(Priv(at(ive)?)?)',
     'msg' => "The correct UD label for privative (abessive) case is 'Case=Abe'."},
    {'re'  => 'Case=(Temp(or(al(is)?)?)?)',
     'msg' => "The correct UD label for temporal case is 'Case=Tem'."},
    {'re'  => 'Aspect=Pro',
     'msg' => "The correct UD v2 label for prospective aspect is 'Aspect=Prosp'."}, # this was renamed between v1 and v2 guidelines
    {'re'  => '(Aspect=Perfect|Tense=Perf(ect)?)',
     'msg' => "Use 'Aspect=Perf' to distinguish perfect from other forms."},
    {'re'  => 'Tense=(Pra?et(er(ite?)?)?|Prt[12]?)',
     'msg' => "The correct UD label for preterit is 'Tense=Past'."},
    {'re'  => 'Mood=Cond',
     'msg' => "The correct UD label for conditional mood is 'Mood=Cnd'."},
    {'re'  => 'Mood=Co?nj(un(c(t(ive?)?)?)?)?',
     'msg' => "The correct UD label for conjunctive/subjunctive mood is 'Mood=Sub'."},
    {'re'  => 'Mood=Subj(un(c(t(ive?)?)?)?)?',
     'msg' => "The correct UD label for conjunctive/subjunctive mood is 'Mood=Sub'."},
    {'re'  => 'Mood=Quot(at(ive?)?)?',
     'msg' => "The correct UD label for quotative mood is 'Mood=Qot'."},
    {'re'  => 'Voice=(Anti|Antipas(s(ive?)?)?)',
     'msg' => "The correct UD label for antipassive voice is 'Voice=Antip'."},
    {'re'  => 'VerbForm=Finite?',
     'msg' => "The correct UD label for finite verbs is 'VerbForm=Fin'."},
    {'re'  => 'VerbForm=Trans',
     'msg' => "The correct UD v2 label for transgressive/converb is 'VerbForm=Conv'."}, # this was renamed between v1 and v2 guidelines
    {'re'  => 'ExtPos=(?!(NOUN|PROPN|PRON|ADJ|DET|NUM|VERB|AUX|ADV|ADP|SCONJ|CCONJ|PART|INTJ|SYM|PUNCT|X))',
     'msg' => "Only defined UPOS tags can be used as values of 'ExtPos'."},
    {'re'  => '.*=(None|Unsp(ec(ified)?)?)',
     'msg' => "If a feature does not apply to a word, UD simply omits the feature."}
);

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
# Remember lowercase-truecase mapping for all globally defined features.
# We will later check that language-specific redefinitions match the case.
my %global_lc = ();
foreach my $file (@gdfiles)
{
    my $feature = $file;
    $feature =~ s/\.md$//;
    # Layered features have [brackets] in the name but the file name uses a hyphen and no brackets.
    $feature =~ s/^([A-Za-z0-9]+)-([a-z]+)$/$1\[$2\]/;
    if(grep {$_ eq $feature} (@ufeats))
    {
        $hash{$feature}{type} = 'universal';
    }
    else
    {
        $hash{$feature}{type} = 'global';
    }
    if($feature !~ m/^[A-Z][A-Za-z0-9]*(\[[a-z]+\])?$/)
    {
        push(@{$hash{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
    }
    $global_lc{lc($feature)} = $feature;
    read_feature_doc($feature, "$gdfeats/$file", $hash{$feature}, \@deviations);
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
        # Layered features have [brackets] in the name but the file name uses a hyphen and no brackets.
        $feature =~ s/^([A-Za-z0-9]+)-([a-z]+)$/$1\[$2\]/;
        if(grep {$_ eq $feature} (@ufeats))
        {
            $lhash{$lcode}{$feature}{type} = 'universal';
        }
        else
        {
            $lhash{$lcode}{$feature}{type} = 'local';
        }
        if($feature !~ m/^[A-Z][A-Za-z0-9]*(\[[a-z]+\])?$/)
        {
            push(@{$lhash{$lcode}{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
        }
        # Language-specific feature name must either be identical to a globally defined feature,
        # or it must differ from all globally defined features in more than just case.
        my $lcfeature = lc($feature);
        if(exists($global_lc{$lcfeature}) && $feature ne $global_lc{$lcfeature})
        {
            push(@{$lhash{$lcode}{$feature}{errors}}, "Feature name '$feature' differs from globally defined '$global_lc{$lcfeature}' in case.");
        }
        my $corresponding_global = undef;
        if(exists($hash{$feature}))
        {
            $corresponding_global = $hash{$feature};
        }
        read_feature_doc($feature, "$ldfeats/$file", $lhash{$lcode}{$feature}, \@deviations, $corresponding_global);
    }
}
# Before printing the data, remove all values from features with errors.
foreach my $f (keys(%hash))
{
    if(scalar(@{$hash{$f}{errors}}) > 0)
    {
        $hash{$f}{values} = [];
    }
}
foreach my $l (keys(%lhash))
{
    foreach my $f (keys(%{$lhash{$l}}))
    {
        if(scalar(@{$lhash{$l}{$f}{errors}}) > 0)
        {
            $lhash{$l}{$f}{values} = [];
        }
    }
}
# Print an overview of the features we found.
print_json(\%hash, \%lhash, \@deviations, $docs, "$scriptpath/docfeats.json");
# There is now a larger JSON about features of individual languages which
# depends on the contents of docfeats.json generated here.
# The following reader will also read the file docfeats.json we just wrote,
# and project it to the larger data structure. We thus only need to write the
# structure again to update its representation on the disk.
my $data = valdata::read_feats_json($scriptpath);
valdata::write_feats_json($data, "$scriptpath/feats.json");



#------------------------------------------------------------------------------
# Reads a MarkDown file that documents one feature.
#------------------------------------------------------------------------------
sub read_feature_doc
{
    my $feature = shift; # the name of the feature
    my $filepath = shift; # the name and path to the corresponding file
    my $feathash = shift; # hash reference
    my $deviations = shift; # array reference
    my $global = shift; # hash reference to the global definition of the same feature if it exists and if this one is local
    # We will want to check that people do not redefine global feature values
    # by only changing capitalization, hence we need the global values in
    # normalized case.
    my %global_lc = ();
    if(defined($global))
    {
        foreach my $value (@{$global->{values}})
        {
            $global_lc{lc($value)} = $value;
        }
    }
    my $title = '';
    my $udver = 1;
    my @values = ();
    my %valdoc;
    my $current_value;
    my @unrecognized_example_lines;
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
        # The following lines should occur in the MarkDown header (between two '---' lines).
        # We take the risk and do not check where exactly they occur.
        if(m/^title:\s*'(.+?)'$/)
        {
            $title = $1;
        }
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
            # Check for known and banned deviations from universal features.
            my $fv = "$feature=$value";
            foreach my $d (@{$deviations})
            {
                if($fv =~ m/^$d->{re}$/i)
                {
                    push(@{$feathash->{errors}}, "Wrong value '$value'. $d->{msg}");
                }
            }
            if(defined($global))
            {
                my $lcvalue = lc($value);
                if(exists($global_lc{$lcvalue}) && $value ne $global_lc{$lcvalue})
                {
                    push(@{$feathash->{errors}}, "Wrong value '$value'. It differs from globally defined '$global_lc{$lcvalue}' in case.");
                }
            }
        }
        # Warn about unrecognized level 3 headings.
        # Note that there are some examples of legitimate level 3 headings that are not feature values.
        # References is one such case. The "Prague Dependency Treebank" exception is needed if there is a Diff section (level 2) with treebanks that currently differ from the overall guidelines.
        elsif(m/^\#\#\#[^\#]/ && !m/^\#\#\#\s*(References|Notes|Prague Dependency Treebank|Turku Dependency Treebank|Russian National Corpus|Conversion from JOS|Ukrainian Dependency Treebank)$/)
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
        $first_line = 0;
    }
    close(FILE);
    if(defined($current_value) && $valdoc{$current_value}{examples} == 0)
    {
        push(@{$feathash->{errors}}, "No examples found under value '$current_value'.", @unrecognized_example_lines);
    }
    if($title eq '')
    {
        push(@{$feathash->{errors}}, "No title found in the header.");
    }
    elsif($title ne $feature)
    {
        push(@{$feathash->{errors}}, "Header title '$title' does not match the file name '$feature'.");
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



#------------------------------------------------------------------------------
# Prints a JSON structure with documented feature-value pairs for each UD
# language.
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
        my @fvpairs = ();
        # Add locally defined (or redefined) features.
        if(exists($lhash->{$lcode}))
        {
            foreach my $feature (sort(keys(%{$lhash->{$lcode}})))
            {
                # Skip the feature if there are errors in its documentation.
                unless(scalar(@{$lhash->{$lcode}{$feature}{errors}}) > 0)
                {
                    foreach my $value (sort(@{$lhash->{$lcode}{$feature}{values}}))
                    {
                        push(@fvpairs, "$feature=$value");
                    }
                }
            }
        }
        # Add globally defined features that are not redefined locally.
        foreach my $feature (sort(keys(%{$ghash})))
        {
            unless(exists($lhash->{$lcode}{$feature}))
            {
                # Skip the feature if there are errors in its documentation.
                unless(scalar(@{$ghash->{$feature}{errors}}) > 0)
                {
                    foreach my $value (sort(@{$ghash->{$feature}{values}}))
                    {
                        push(@fvpairs, "$feature=$value");
                    }
                }
            }
        }
        push(@jsonlines, '"'.valdata::escape_json_string($lcode).'": ['.join(', ', map {'"'.valdata::escape_json_string($_).'"'} (@fvpairs)).']');
    }
    $json .= join(",\n", @jsonlines)."\n";
    $json .= "},\n"; # end of lists
    $json .= "\"gdocs\": {\n";
    my @featurelines = ();
    foreach my $feature (sort(keys(%{$ghash})))
    {
        push(@featurelines, '"'.valdata::escape_json_string($feature).'": '.encode_feature_json($ghash->{$feature}));
    }
    $json .= join(",\n", @featurelines)."\n";
    $json .= "},\n"; # end of gdocs
    $json .= "\"ldocs\": {\n";
    my @languagelines = ();
    foreach my $lcode (sort(keys(%{$lhash})))
    {
        my @features = sort(keys(%{$lhash->{$lcode}}));
        if(scalar(@features) > 0)
        {
            my $languageline = "\"$lcode\": {\n";
            @featurelines = ();
            foreach my $feature (@features)
            {
                push(@featurelines, '"'.valdata::escape_json_string($feature).'": '.encode_feature_json($lhash->{$lcode}{$feature}));
            }
            $languageline .= join(",\n", @featurelines)."\n";
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
sub encode_feature_json
{
    my $feature = shift; # hash reference
    my $json = '{';
    $json .= '"type": "'.valdata::escape_json_string($feature->{type}).'", ';
    $json .= '"values": ['.join(', ', map {'"'.valdata::escape_json_string($_).'"'} (@{$feature->{values}})).'], ';
    $json .= '"errors": ['.join(', ', map {'"'.valdata::escape_json_string($_).'"'} (@{$feature->{errors}})).']';
    $json .= '}';
    return $json;
}
