# Functions to read and write JSON files with UD validation data. There are
# several scripts that need to access various JSON files with features,
# dependency relations etc.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

package valdata;

use Carp;
use JSON::Parse 'json_file_to_perl';
use utf8;



#------------------------------------------------------------------------------
# Reads the data about features in each language (feats.json), and the current
# state of documentation (docfeats.json). Updates the main data with the info
# about documentation, and returns a reference to the combined hash.
#------------------------------------------------------------------------------
sub read_feats_json
{
    my $path = shift; # docs-automation/valrules
    my $docs = read_feats_json1($path);
    my $data = json_file_to_perl("$path/feats.json")->{features};
    merge_documented_and_declared_features($docs, $data);
    return $data;
}



#------------------------------------------------------------------------------
# Takes references to two hashes: features known from documentation and
# features declared to be used in a given language. Both hashes have a similar
# structure: $hash->{$lcode}{$feature}{...}. The first hash should reflect the
# current state of the docs repository. Information on documentation of
# features will be taken from the first hash and copied to the second hash
# (where it will replace any such information that may be there from the past).
# The remaining values in the second hash will be adjusted accordingly. For
# example, a feature value that was previously permitted may now be disallowed
# if it disappeared from documentation. On the other hand, the second hash has
# the say in usage of the features with particular UPOS tags (the first hash
# probably does not have such information anyway).
#
# The copies made here are not necessarily deep. We assume that the first hash
# will not be further used. It is thus possible (but not guaranteed) that the
# two hashes will share references to some substructures after merging.
#------------------------------------------------------------------------------
sub merge_documented_and_declared_features
{
    my $documented = shift; # hash ref
    my $declared = shift; # hash ref
    # Copy documented features to declared.
    foreach my $lcode (keys(%{$documented}))
    {
        foreach my $f (keys(%{$documented->{$lcode}}))
        {
            # If the feature has not been previously used in the language, just add it.
            if(!exists($declared->{$lcode}{$f}))
            {
                $declared->{$lcode}{$f} = $documented->{$lcode}{$f};
                my $decf = $declared->{$lcode}{$f};
                $decf->{uvalues} = [] if(!defined($decf->{uvalues}));
                $decf->{unused_uvalues} = [] if(!defined($decf->{unused_uvalues}));
                $decf->{lvalues} = [] if(!defined($decf->{lvalues}));
                $decf->{unused_lvalues} = [] if(!defined($decf->{unused_lvalues}));
                $decf->{evalues} = [] if(!defined($decf->{evalues}));
                $decf->{errors} = [] if(!defined($decf->{errors}));
                # The feature will not be permitted until at least one value is turned on for at least one UPOS tag.
                $decf->{permitted} = 0;
                @{$decf->{unused_uvalues}} = (@{$decf->{uvalues}}, @{$decf->{unused_uvalues}});
                $decf->{uvalues} = [];
                @{$decf->{unused_lvalues}} = (@{$decf->{lvalues}}, @{$decf->{unused_lvalues}});
                $decf->{lvalues} = [];
            }
            # If the feature has been previously used in the language, check its status and permitted values.
            else
            {
                my $decf = $declared->{$lcode}{$f};
                my $docf = $documented->{$lcode}{$f};
                $decf->{type} = $docf->{type};
                $decf->{doc} = $docf->{doc};
                $decf->{errors} = $docf->{errors};
                $decf->{errors} = [] if(!defined($decf->{errors}));
                my %docuvalues; map {$docuvalues{$_}++} (@{$docf->{uvalues}}, @{$docf->{unused_uvalues}});
                my %doclvalues; map {$doclvalues{$_}++} (@{$docf->{lvalues}}, @{$docf->{unused_lvalues}});
                my %docevalues; map {$docevalues{$_}++} (@{$docf->{evalues}});
                # Before we replace any values in the target hash, save the current
                # set of values. Some of them may not appear in the new documentation
                # but we still want to preserve them at least as evalues. (The new
                # documentation may contain oversight errors which will be quickly
                # fixed, and we do not want the user to lose all information on the
                # feature because of a short-lived error.)
                my %decvalues; map {$decvalues{$_}++} (@{$decf->{uvalues}}, @{$decf->{unused_uvalues}}, @{$decf->{lvalues}}, @{$decf->{unused_lvalues}}, @{$decf->{evalues}});
                # Previously declared values that the current documentation does not
                # classify as permitted will go to evalues (they may or may not already
                # be there).
                foreach my $v (keys(%decvalues))
                {
                    if(!exists($docuvalues{$v}) && !exists($doclvalues{$v}))
                    {
                        $docevalues{$v}++;
                    }
                }
                # Now the %doc[ule]values hashes contain all known values, documented or declared.
                # Sort the documented values as either used or unused, based on the $decf hash.
                # Aggregate feature-value pairs over all UPOS categories.
                my %used;
                foreach my $u (keys(%{$decf->{byupos}}))
                {
                    foreach my $v (keys(%{$decf->{byupos}{$u}}))
                    {
                        $used{$v}++;
                    }
                }
                # There are boolean universal features that do not depend on the language.
                # Always allow them even if they have not been used in the data so far.
                if($f =~ m/^(Abbr|Foreign|Typo)$/)
                {
                    $used{'Yes'}++;
                }
                @{$decf->{uvalues}} = grep {exists($used{$_})} (keys(%docuvalues));
                @{$decf->{unused_uvalues}} = grep {!exists($used{$_})} (keys(%docuvalues));
                @{$decf->{lvalues}} = grep {exists($used{$_})} (keys(%doclvalues));
                @{$decf->{unused_lvalues}} = grep {!exists($used{$_})} (keys(%doclvalues));
                @{$decf->{evalues}} = keys(%docevalues);
                $decf->{permitted} = scalar(@{$decf->{uvalues}}) + scalar(@{$decf->{lvalues}}) > 0;
            }
        }
        # If a whole feature was previously declared and disappeared from documentation,
        # move all its values to evalues.
        foreach my $f (keys(%{$declared->{$lcode}}))
        {
            if(!exists($documented->{$lcode}{$f}))
            {
                my $decf = $declared->{$lcode}{$f};
                $decf->{permitted} = 0;
                @{$decf->{evalues}} = (@{$decf->{uvalues}}, @{$decf->{unused_uvalues}}, @{$decf->{lvalues}}, @{$decf->{unused_lvalues}}, @{$decf->{evalues}});
                $decf->{uvalues} = [];
                $decf->{unused_uvalues} = [];
                $decf->{lvalues} = [];
                $decf->{unused_lvalues} = [];
                $decf->{errors} = [];
            }
        }
    }
}



#------------------------------------------------------------------------------
# Reads the data about documented features from the JSON file. Returns a hash
# reference. This is a variant of the older function, still partially needed.
#------------------------------------------------------------------------------
sub read_feats_json1
{
    my $path = shift;
    # Read the temporary JSON file with documented features.
    my $docfeats = json_file_to_perl("$path/docfeats.json");
    # Get the universal features and values from the global documentation.
    my %universal;
    if(exists($docfeats->{gdocs}) && ref($docfeats->{gdocs}) eq 'HASH')
    {
        foreach my $f (keys(%{$docfeats->{gdocs}}))
        {
            if($docfeats->{gdocs}{$f}{type} eq 'universal')
            {
                foreach my $v (@{$docfeats->{gdocs}{$f}{values}})
                {
                    $universal{$f}{$v}++;
                }
            }
        }
    }
    else
    {
        confess("No globally documented features found in the JSON file");
    }
    # Create the combined data structure we will need in this script.
    my %data;
    # $docfeats->{lists} should contain all languages known in UD, so we will use its index.
    if(exists($docfeats->{lists}) && ref($docfeats->{lists}) eq 'HASH')
    {
        my @lcodes = keys(%{$docfeats->{lists}});
        foreach my $lcode (@lcodes)
        {
            $data{$lcode} = {};
            # If the language has any local documentation, read it first.
            if(exists($docfeats->{ldocs}{$lcode}))
            {
                copy_features_from_local_documentation($docfeats->{ldocs}{$lcode}, $data{$lcode}, \%universal);
            }
            # Read the global documentation and add features that were not documented locally.
            copy_features_from_global_documentation($docfeats->{gdocs}, $data{$lcode}, \%universal, $declfeats->{$lcode});
        }
    }
    else
    {
        confess("No documented features found in the JSON file");
    }
    return \%data;
}



#------------------------------------------------------------------------------
# Reads the data about documented features from the JSON file. Returns a hash
# reference. This is the older reading function, now deprecated. It combines
# various source files but it does not read the previously combined feats.json,
# so it discards anything that was edited through the web interface.
#------------------------------------------------------------------------------
sub read_feats_json0
{
    my $path = shift;
    # Read the temporary JSON file with documented features.
    my $docfeats = json_file_to_perl("$path/docfeats.json");
    # Read the temporary JSON file with features declared in tools/data.
    my $declfeats = json_file_to_perl("$path/declfeats.json");
    # Read the temporary JSON file with features collected from treebank data.
    my $datafeats = json_file_to_perl("$path/datafeats.json");
    # Get the universal features and values from the global documentation.
    my %universal;
    if(exists($docfeats->{gdocs}) && ref($docfeats->{gdocs}) eq 'HASH')
    {
        foreach my $f (keys(%{$docfeats->{gdocs}}))
        {
            if($docfeats->{gdocs}{$f}{type} eq 'universal')
            {
                foreach my $v (@{$docfeats->{gdocs}{$f}{values}})
                {
                    $universal{$f}{$v}++;
                }
            }
        }
    }
    else
    {
        confess("No globally documented features found in the JSON file");
    }
    # Create the combined data structure we will need in this script.
    my %data;
    # $docfeats->{lists} should contain all languages known in UD, so we will use its index.
    if(exists($docfeats->{lists}) && ref($docfeats->{lists}) eq 'HASH')
    {
        my @lcodes = keys(%{$docfeats->{lists}});
        foreach my $lcode (@lcodes)
        {
            $data{$lcode} = {};
            # If the language has any local documentation, read it first.
            if(exists($docfeats->{ldocs}{$lcode}))
            {
                copy_features_from_local_documentation($docfeats->{ldocs}{$lcode}, $data{$lcode}, \%universal);
            }
            # Read the global documentation and add features that were not documented locally.
            copy_features_from_global_documentation0($docfeats->{gdocs}, $data{$lcode}, \%universal, $declfeats->{$lcode});
            # Save features that were declared in tools/data but are not documented and thus not permitted.
            if(defined($declfeats->{$lcode}))
            {
                copy_declared_but_undocumented_features($declfeats->{$lcode}, $data{$lcode});
            }
            # Check the feature values actually used in the treebank data.
            # Remove unused values from the permitted features.
            # Revoke the permission of the feature if no values remain.
            copy_feature_value_usage($datafeats->{$lcode}, $data{$lcode});
        }
    }
    else
    {
        confess("No documented features found in the JSON file");
    }
    return \%data;
}



#------------------------------------------------------------------------------
# Copies feature from local language-specific documentation. This should happen
# before global documentation of the same feature is checked, and global
# documentation should be ignored if local exists.
#------------------------------------------------------------------------------
sub copy_features_from_local_documentation
{
    my $ldoc = shift; # hash ref, from $docfeats->{ldocs}{$lcode}
    my $data = shift; # target hash ref, from $data{$lcode}
    my $universal = shift; # hash ref, keys are universal features, under them values
    my @features = keys(%{$ldoc});
    foreach my $f (@features)
    {
        # Type is 'universal' or 'lspec'. A universal feature stays universal
        # even if it is locally documented and some language-specific values are added.
        if(exists($universal->{$f}))
        {
            $data->{$f}{type} = 'universal';
            # Get the universally valid values of the feature.
            my @uvalues = ();
            my @lvalues = ();
            foreach my $v (@{$ldoc->{$f}{values}})
            {
                if(exists($universal->{$f}{$v}))
                {
                    push(@uvalues, $v);
                }
                else
                {
                    push(@lvalues, $v);
                }
            }
            $data->{$f}{uvalues} = \@uvalues;
            $data->{$f}{lvalues} = \@lvalues;
            $data->{$f}{evalues} = [];
        }
        else
        {
            $data->{$f}{type} = 'lspec';
            $data->{$f}{uvalues} = [];
            $data->{$f}{lvalues} = $ldoc->{$f}{values};
            $data->{$f}{evalues} = [];
        }
        # Documentation can be 'global', 'local', 'gerror', 'lerror'.
        if(scalar(@{$ldoc->{$f}{errors}}) > 0)
        {
            $data->{$f}{doc} = 'lerror';
            $data->{$f}{errors} = $ldoc->{$f}{errors};
        }
        else
        {
            $data->{$f}{doc} = 'local';
            $data->{$f}{permitted} = 1;
            # In theory we should also require that the feature is universal or
            # if it is language-specific, that its values were declared in tools/data.
            # However, if the values are locally documented and the documentation is error-free,
            # we can assume that they are really valid for this language.
        }
    }
}



#------------------------------------------------------------------------------
# Copies feature from global documentation (these may still be non-universal,
# i.e., technically language-specific. This should happen after local
# documentation has been checked, and global documentation should be ignored
# if local exists.
#------------------------------------------------------------------------------
sub copy_features_from_global_documentation
{
    my $gdoc = shift; # hash ref, from $docfeats->{gdocs}
    my $data = shift; # target hash ref, from $data{$lcode} (we read global documentation into language-specific feature inventories)
    my $universal = shift; # hash ref, keys are universal features, under them values
    # Read the global documentation and add features that were not documented locally.
    my @features = keys(%{$gdoc});
    foreach my $f (@features)
    {
        # Skip globally documented features that have local documentation (even if with errors).
        next if(exists($data->{$f}));
        # Type is 'universal' or 'lspec'.
        if(exists($universal->{$f}))
        {
            $data->{$f}{type} = 'universal';
            # This is global documentation of universal feature, thus all values are universal.
            $data->{$f}{uvalues} = $gdoc->{$f}{values};
            $data->{$f}{lvalues} = [];
            $data->{$f}{evalues} = [];
        }
        else
        {
            $data->{$f}{type} = 'lspec';
            $data->{$f}{uvalues} = [];
            $data->{$f}{lvalues} = $gdoc->{$f}{values};
            $data->{$f}{evalues} = [];
        }
        # Documentation can be 'global', 'local', 'gerror', 'lerror'.
        if(scalar(@{$gdoc->{$f}{errors}}) > 0)
        {
            $data->{$f}{doc} = 'gerror';
            $data->{$f}{errors} = $gdoc->{$f}{errors};
        }
        else
        {
            $data->{$f}{doc} = 'global';
            # The feature is permitted in this language if it is universal or it has at least one documented language-specific value.
            $data->{$f}{permitted} = $data->{$f}{type} eq 'universal' || scalar(@{$data->{$f}{lvalues}}) > 0;
        }
    }
}



#------------------------------------------------------------------------------
# Copies feature from global documentation (these may still be non-universal,
# i.e., technically language-specific. This should happen after local
# documentation has been checked, and global documentation should be ignored
# if local exists.
#------------------------------------------------------------------------------
sub copy_features_from_global_documentation0
{
    my $gdoc = shift; # hash ref, from $docfeats->{gdocs}
    my $data = shift; # target hash ref, from $data{$lcode} (we read global documentation into language-specific feature inventories)
    my $universal = shift; # hash ref, keys are universal features, under them values
    my $declared = shift; # array ref, feature-values from $declfeats->{$lcode} ###!!! only needed temporarily in this function!
    # Read the global documentation and add features that were not documented locally.
    my @features = keys(%{$gdoc});
    foreach my $f (@features)
    {
        # Skip globally documented features that have local documentation (even if with errors).
        next if(exists($data->{$f}));
        # Type is 'universal' or 'lspec'.
        if(exists($universal->{$f}))
        {
            $data->{$f}{type} = 'universal';
            # This is global documentation of universal feature, thus all values are universal.
            $data->{$f}{uvalues} = $gdoc->{$f}{values};
            $data->{$f}{lvalues} = [];
            $data->{$f}{evalues} = [];
        }
        else
        {
            $data->{$f}{type} = 'lspec';
            $data->{$f}{uvalues} = [];
            ###!!! The following filter should later be removed because the globally documented language-specific features will be turned on in the web interface.
            # This is global documentation but the feature is not universal, thus we allow only
            # those values that were declared in tools/data (if they are mentioned in the documentation).
            my @lvalues = ();
            if(defined($declared))
            {
                foreach my $v (@{$gdoc->{$f}{values}})
                {
                    my $fv = "$f=$v";
                    if(grep {$_ eq $fv} (@{$declared}))
                    {
                        push(@lvalues, $v);
                    }
                }
            }
            $data->{$f}{lvalues} = \@lvalues;
            $data->{$f}{evalues} = [];
        }
        # Documentation can be 'global', 'local', 'gerror', 'lerror'.
        if(scalar(@{$gdoc->{$f}{errors}}) > 0)
        {
            $data->{$f}{doc} = 'gerror';
            $data->{$f}{errors} = $gdoc->{$f}{errors};
        }
        else
        {
            $data->{$f}{doc} = 'global';
            # The feature is permitted in this language if it is universal or at least one of its documented values was declared in tools/data.
            $data->{$f}{permitted} = $data->{$f}{type} eq 'universal' || scalar(@{$data->{$f}{lvalues}}) > 0;
        }
    }
}



#------------------------------------------------------------------------------
# Copies feature values that were declared in tools/data/feat_val.xx but they
# cannot be used because they are not documented.
#------------------------------------------------------------------------------
sub copy_declared_but_undocumented_features
{
    my $declared = shift; # array ref, feature-values from $declfeats->{$lcode}
    my $data = shift; # target hash ref, from $data{$lcode}
    my @fvs = @{$declared};
    foreach my $fv (@fvs)
    {
        if($fv =~ m/^(.+)=(.+)$/)
        {
            my $f = $1;
            my $v = $2;
            if(exists($data->{$f}))
            {
                my $fdata = $data->{$f};
                my @known = (@{$fdata->{uvalues}}, @{$fdata->{lvalues}}, @{$fdata->{evalues}});
                if(!grep {$_ eq $v} (@known))
                {
                    # evalues may already exist and contain values that appeared in documentation which contains errors.
                    # Now it will also contain values that were declared but not documented. In any case, those values
                    # are not permitted in the data.
                    push(@{$fdata->{evalues}}, $v);
                }
            }
            else
            {
                $data->{$f}{type} = 'lspec';
                $data->{$f}{doc} = 'none';
                $data->{$f}{permitted} = 0;
                $data->{$f}{uvalues} = [];
                $data->{$f}{lvalues} = [];
                $data->{$f}{evalues} = [];
                push(@{$data->{$f}{evalues}}, $v);
            }
        }
        else
        {
            confess("Cannot parse declared feature-value '$fv'");
        }
    }
}



#------------------------------------------------------------------------------
# For features permitted in the past (i.e., either universal, or declared,
# regardless of documentation), copy the statistics of values that were
# actually used in data. Values that were not used so far will be moved to
# separate lists (uvalues to unused_uvalues, lvalues to unused_lvalues). This
# may render the feature unpermitted if no values remain.
#------------------------------------------------------------------------------
sub copy_feature_value_usage
{
    my $dfupos = shift; # hash ref, from $datafeats->{$lcode}
    my $data = shift; # target hash ref, from $data{$lcode}
    # Aggregate feature-value pairs over all UPOS categories.
    my %dfall;
    if(defined($dfupos))
    {
        foreach my $u (keys(%{$dfupos}))
        {
            foreach my $f (keys(%{$dfupos->{$u}}))
            {
                foreach my $v (keys(%{$dfupos->{$u}{$f}}))
                {
                    $dfall{$f}{$v}++;
                    # Make the UPOS-specific statistics of features available in the combined database.
                    # $dfupos may contain feature values that are not valid according to the current rules (i.e., they are not documented).
                    # Do not add such feature values to the 'byupos' hash. Discard them.
                    if(exists($data->{$f}) && grep {$_ eq $v} (@{$data->{$f}{uvalues}}, @{$data->{$f}{lvalues}}))
                    {
                        $data->{$f}{byupos}{$u}{$v} = $dfupos->{$u}{$f}{$v};
                    }
                }
            }
        }
    }
    # Disallow previously permitted values if they were never used in the data.
    foreach my $f (keys(%{$data}))
    {
        # There are boolean universal features that do not depend on the language.
        # Always allow them even if they have not been used in the data so far.
        next if($f =~ m/^(Abbr|Foreign|Typo)$/);
        if($data->{$f}{permitted})
        {
            my @values = @{$data->{$f}{uvalues}};
            $data->{$f}{uvalues} = [];
            $data->{$f}{unused_uvalues} = [];
            foreach my $v (@values)
            {
                if(exists($dfall{$f}{$v}))
                {
                    push(@{$data->{$f}{uvalues}}, $v);
                }
                else
                {
                    push(@{$data->{$f}{unused_uvalues}}, $v);
                }
            }
            @values = @{$data->{$f}{lvalues}};
            $data->{$f}{lvalues} = [];
            $data->{$f}{unused_lvalues} = [];
            foreach my $v (@values)
            {
                if(exists($dfall{$f}{$v}))
                {
                    push(@{$data->{$f}{lvalues}}, $v);
                }
                else
                {
                    push(@{$data->{$f}{unused_lvalues}}, $v);
                }
            }
            my $n = scalar(@{$data->{$f}{uvalues}}) + scalar(@{$data->{$f}{lvalues}});
            if($n==0)
            {
                $data->{$f}{permitted} = 0;
            }
        }
    }
}



#------------------------------------------------------------------------------
# Dumps the feature data as a JSON file.
#------------------------------------------------------------------------------
sub write_feats_json
{
    # Initially, the data is read from the Python code.
    # This will change in the future and we will read the JSON file instead!
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl instead.",'."\n\n";
    $json .= '"features": {'."\n";
    my @ljsons = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my $ljson = '"'.$lcode.'"'.": {\n";
        my @fjsons = ();
        my @features = sort(keys(%{$data->{$lcode}}));
        foreach my $f (@features)
        {
            # Do not write features that are not available in this language and
            # nobody even attempted to make them available.
            my $nuv = scalar(@{$data->{$lcode}{$f}{uvalues}});
            my $nlv = scalar(@{$data->{$lcode}{$f}{lvalues}});
            my $nuuv = defined($data->{$lcode}{$f}{unused_uvalues}) ? scalar(@{$data->{$lcode}{$f}{unused_uvalues}}) : 0;
            my $nulv = defined($data->{$lcode}{$f}{unused_lvalues}) ? scalar(@{$data->{$lcode}{$f}{unused_lvalues}}) : 0;
            my $nev = scalar(@{$data->{$lcode}{$f}{evalues}});
            my $nerr = defined($data->{$lcode}{$f}{errors}) ? scalar(@{$data->{$lcode}{$f}{errors}}) : 0;
            next if($nuv+$nlv+$nuuv+$nulv+$nev+$nerr == 0);
            # Also skip features that are documented globally and not permitted in this language.
            next if($data->{$lcode}{$f}{doc} eq 'global' && !$data->{$lcode}{$f}{permitted});
            my $fjson = '"'.escape_json_string($f).'": {';
            $fjson .= '"type": "'.escape_json_string($data->{$lcode}{$f}{type}).'", '; # universal lspec
            $fjson .= '"doc": "'.escape_json_string($data->{$lcode}{$f}{doc}).'", '; # global gerror local lerror none
            $fjson .= '"permitted": '.($data->{$lcode}{$f}{permitted} ? 1 : 0).', '; # 1 0
            my @ajsons = ();
            foreach my $array (qw(errors uvalues lvalues unused_uvalues unused_lvalues evalues))
            {
                my $ajson .= '"'.$array.'": [';
                if(defined($data->{$lcode}{$f}{$array}))
                {
                    $ajson .= join(', ', map {'"'.escape_json_string($_).'"'} (sort(@{$data->{$lcode}{$f}{$array}})));
                }
                $ajson .= ']';
                push(@ajsons, $ajson);
            }
            $fjson .= join(', ', @ajsons).', ';
            $fjson .= '"byupos": {';
            my @ujsons = ();
            my @upos = sort(keys(%{$data->{$lcode}{$f}{byupos}}));
            foreach my $u (@upos)
            {
                my $ujson = '"'.escape_json_string($u).'": {';
                my @vjsons = ();
                my @values = sort(keys(%{$data->{$lcode}{$f}{byupos}{$u}}));
                foreach my $v (@values)
                {
                    if($data->{$lcode}{$f}{byupos}{$u}{$v} > 0)
                    {
                        push(@vjsons, '"'.escape_json_string($v).'": '.$data->{$lcode}{$f}{byupos}{$u}{$v});
                    }
                }
                $ujson .= join(', ', @vjsons);
                $ujson .= '}';
                push(@ujsons, $ujson);
            }
            $fjson .= join(', ', @ujsons);
            $fjson .= '}'; # byupos
            if(exists($data->{$lcode}{$f}{lastchanged}))
            {
                $fjson .= ', "lastchanged": "'.escape_json_string($data->{$lcode}{$f}{lastchanged}).'"';
            }
            if(exists($data->{$lcode}{$f}{lastchanger}))
            {
                $fjson .= ', "lastchanger": "'.escape_json_string($data->{$lcode}{$f}{lastchanger}).'"';
            }
            $fjson .= '}';
            push(@fjsons, $fjson);
        }
        $ljson .= join(",\n", @fjsons)."\n";
        $ljson .= '}';
        push(@ljsons, $ljson);
    }
    $json .= join(",\n", @ljsons)."\n";
    $json .= "}}\n";
    open(JSON, ">$filename") or confess("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
}



#------------------------------------------------------------------------------
# Reads the data about deprels in each language (deprels.json), and the current
# state of documentation (docdeps.json). Updates the main data with the info
# about documentation, and returns a reference to the combined hash.
#------------------------------------------------------------------------------
sub read_deprels_json
{
    my $path = shift; # docs-automation/valrules
    my $docs = read_documented_deprels_json($path);
    my $data = json_file_to_perl("$path/deprels.json")->{deprels};
    merge_documented_and_declared_deprels($docs, $data);
    return $data;
}



#------------------------------------------------------------------------------
# Reads the JSON about dependency relations that are documented globally and
# for individual languages.
#------------------------------------------------------------------------------
sub read_documented_deprels_json
{
    my $path = shift; # docs-automation/valrules
    my $docdeps = json_file_to_perl("$path/docdeps.json");
    my %data;
    # $docdeps->{lists} should contain all languages known in UD, so we will use its index.
    if(exists($docdeps->{lists}) && ref($docdeps->{lists}) eq 'HASH')
    {
        my @lcodes = keys(%{$docdeps->{lists}});
        foreach my $lcode (@lcodes)
        {
            $data{$lcode} = {};
            # If the language has any local documentation, read it first.
            if(exists($docdeps->{ldocs}{$lcode}))
            {
                my @deprels = keys(%{$docdeps->{ldocs}{$lcode}});
                foreach my $d (@deprels)
                {
                    $data{$lcode}{$d}{type} = $docdeps->{ldocs}{$lcode}{$d}{type};
                    $data{$lcode}{$d}{errors} = $docdeps->{ldocs}{$lcode}{$d}{errors};
                    my $nerr = scalar(@{$data{$lcode}{$d}{errors}});
                    if($nerr > 0)
                    {
                        $data{$lcode}{$d}{doc} = 'lerror';
                        $data{$lcode}{$d}{permitted} = 0;
                    }
                    else
                    {
                        $data{$lcode}{$d}{doc} = 'local';
                        $data{$lcode}{$d}{permitted} = 1;
                    }
                }
            }
            # Read the global documentation and add deprels that were not documented locally.
            my @deprels = keys(%{$docdeps->{gdocs}});
            foreach my $d (@deprels)
            {
                if(!exists($data{$lcode}{$d}))
                {
                    $data{$lcode}{$d}{type} = $docdeps->{gdocs}{$d}{type};
                    $data{$lcode}{$d}{errors} = $docdeps->{gdocs}{$d}{errors};
                    my $nerr = scalar(@{$data{$lcode}{$d}{errors}});
                    if($nerr > 0)
                    {
                        $data{$lcode}{$d}{doc} = 'gerror';
                        $data{$lcode}{$d}{permitted} = 0;
                    }
                    else
                    {
                        $data{$lcode}{$d}{doc} = 'global';
                        $data{$lcode}{$d}{permitted} = 1;
                    }
                }
            }
        }
    }
    else
    {
        confess("No documented dependency relations found in the JSON file");
    }
    return \%data;
}



#------------------------------------------------------------------------------
# Takes references to two hashes: deprels known from documentation and
# deprels declared to be used in a given language. Both hashes have a similar
# structure: $hash->{$lcode}{$deprel}{...}. The first hash should reflect the
# current state of the docs repository. Information on documentation of
# deprels will be taken from the first hash and copied to the second hash
# (where it will replace any such information that may be there from the past).
# The remaining values in the second hash will be adjusted accordingly. For
# example, a deprel that was previously permitted may now be disallowed if it
# disappeared from documentation. On the other hand, if the deprel was
# previously not permitted for the language, documentation will not
# automatically allow it.
#
# The copies made here are not necessarily deep. We assume that the first hash
# will not be further used. It is thus possible (but not guaranteed) that the
# two hashes will share references to some substructures after merging.
#------------------------------------------------------------------------------
sub merge_documented_and_declared_deprels
{
    my $documented = shift; # hash ref
    my $declared = shift; # hash ref
    # Copy documented features to declared.
    foreach my $lcode (keys(%{$documented}))
    {
        my $n_declared = scalar(keys(%{$declared->{$lcode}}));
        foreach my $d (keys(%{$documented->{$lcode}}))
        {
            # If the deprel has not been previously used in the language, just add it.
            if(!exists($declared->{$lcode}{$d}))
            {
                $declared->{$lcode}{$d} = $documented->{$lcode}{$d};
                my $decd = $declared->{$lcode}{$d};
                $decd->{errors} = [] if(!defined($decd->{errors}));
                # A new deprel is not permitted until it is turned on for the language in the web interface.
                # Even for universal features, we should not automatically permit them, because then people
                # could not turn them off. After turning off a universal relation, it will be deleted from
                # the language-specific part of the JSON. Only if this is a new language, we will automatically
                # turn on all universal deprels so that the user does not have to permit them one-by-one.
                $decd->{permitted} = $n_declared == 0 && $decd->{type} eq 'universal';
            }
            # If the deprel has been previously used in the language, check its status.
            else
            {
                my $decd = $declared->{$lcode}{$d};
                my $docd = $documented->{$lcode}{$d};
                # If it was previously permitted and the new documentation permits it, it will continue to be permitted.
                $decd->{permitted} = $decd->{permitted} && $docd->{permitted};
                # Universal or local language-specific deprel is permitted if it was previously permitted or if it had previously problems with documentation.
                # In other cases, the deprel may have been previously turned off manually. It will not be permitted until it is turned on manually again.
                if(!$decd->{permitted} && $docd->{permitted} && $decd->{doc} !~ m/^(global|local)$/)
                {
                    $decd->{permitted} = 1;
                }
                $decd->{type} = $docd->{type};
                $decd->{doc} = $docd->{doc};
                $decd->{errors} = $docd->{errors};
                $decd->{errors} = [] if(!defined($decd->{errors}));
            }
        }
        # If a deprel was previously declared and disappeared from documentation,
        # it is no longer permitted.
        foreach my $d (keys(%{$declared->{$lcode}}))
        {
            if(!exists($documented->{$lcode}{$d}))
            {
                my $decd = $declared->{$lcode}{$d};
                $decd->{permitted} = 0;
                $decd->{doc} = 'none';
                $decd->{errors} = [];
            }
        }
    }
}



#------------------------------------------------------------------------------
# Dumps the deprel data as a JSON file.
#------------------------------------------------------------------------------
sub write_deprels_json
{
    # Initially, the data is read from the Python code.
    # This will change in the future and we will read the JSON file instead!
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl instead.",'."\n\n";
    $json .= '"deprels": {'."\n";
    my @ljsons = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my $ljson = '"'.$lcode.'"'.": {\n";
        my @djsons = ();
        my @deprels = sort(keys(%{$data->{$lcode}}));
        foreach my $d (@deprels)
        {
            # Skip deprels that are documented globally and not permitted in this language.
            next if($data->{$lcode}{$d}{doc} eq 'global' && !$data->{$lcode}{$d}{permitted});
            my $djson = '"'.escape_json_string($d).'": {';
            $djson .= '"type": "'.escape_json_string($data->{$lcode}{$d}{type}).'", '; # universal lspec
            $djson .= '"doc": "'.escape_json_string($data->{$lcode}{$d}{doc}).'", '; # global gerror local lerror none
            $djson .= '"permitted": '.($data->{$lcode}{$d}{permitted} ? 1 : 0).', '; # 1 0
            my @ajsons = ();
            foreach my $array (qw(errors))
            {
                my $ajson .= '"'.$array.'": [';
                if(defined($data->{$lcode}{$d}{$array}))
                {
                    $ajson .= join(', ', map {'"'.escape_json_string($_).'"'} (sort(@{$data->{$lcode}{$d}{$array}})));
                }
                $ajson .= ']';
                push(@ajsons, $ajson);
            }
            $djson .= join(', ', @ajsons);
            if(exists($data->{$lcode}{$d}{lastchanged}))
            {
                $djson .= ', "lastchanged": "'.escape_json_string($data->{$lcode}{$d}{lastchanged}).'"';
            }
            if(exists($data->{$lcode}{$d}{lastchanger}))
            {
                $djson .= ', "lastchanger": "'.escape_json_string($data->{$lcode}{$d}{lastchanger}).'"';
            }
            $djson .= '}';
            push(@djsons, $djson);
        }
        $ljson .= join(",\n", @djsons)."\n";
        $ljson .= '}';
        push(@ljsons, $ljson);
    }
    $json .= join(",\n", @ljsons)."\n";
    $json .= "}}\n";
    open(JSON, ">$filename") or confess("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
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



1;
