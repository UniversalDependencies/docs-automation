# Functions to read and write JSON files with UD validation data. There are two
# scripts that need to access feats.json: scan_docs_for_feats.pl and specify_feature.pl.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

package valdata;

use Carp;
use JSON::Parse 'json_file_to_perl';
use utf8;



#------------------------------------------------------------------------------
# Reads the data about documented features from the JSON file.
#------------------------------------------------------------------------------
sub read_data_json
{
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
            if(!exists($lname_by_code{$lcode}))
            {
                confess("Unknown language code '$lcode' in the JSON file");
            }
            # If the language has any local documentation, read it first.
            if(exists($docfeats->{ldocs}{$lcode}))
            {
                my @features = keys(%{$docfeats->{ldocs}{$lcode}});
                foreach my $f (@features)
                {
                    # Type is 'universal' or 'lspec'. A universal feature stays universal
                    # even if it is locally documented and some language-specific values are added.
                    if(exists($universal{$f}))
                    {
                        $data{$lcode}{$f}{type} = 'universal';
                        # Get the universally valid values of the feature.
                        my @uvalues = ();
                        my @lvalues = ();
                        foreach my $v (@{$docfeats->{ldocs}{$lcode}{$f}{values}})
                        {
                            if(exists($universal{$f}{$v}))
                            {
                                push(@uvalues, $v);
                            }
                            else
                            {
                                push(@lvalues, $v);
                            }
                        }
                        $data{$lcode}{$f}{uvalues} = \@uvalues;
                        $data{$lcode}{$f}{lvalues} = \@lvalues;
                        $data{$lcode}{$f}{evalues} = [];
                    }
                    else
                    {
                        $data{$lcode}{$f}{type} = 'lspec';
                        $data{$lcode}{$f}{uvalues} = [];
                        $data{$lcode}{$f}{lvalues} = $docfeats->{ldocs}{$lcode}{$f}{values};
                        $data{$lcode}{$f}{evalues} = [];
                    }
                    # Documentation can be 'global', 'local', 'gerror', 'lerror'.
                    if(scalar(@{$docfeats->{ldocs}{$lcode}{$f}{errors}}) > 0)
                    {
                        $data{$lcode}{$f}{doc} = 'lerror';
                        $data{$lcode}{$f}{errors} = $docfeats->{ldocs}{$lcode}{$f}{errors};
                    }
                    else
                    {
                        $data{$lcode}{$f}{doc} = 'local';
                        $data{$lcode}{$f}{permitted} = 1;
                        # In theory we should also require that the feature is universal or
                        # if it is language-specific, that its values were declared in tools/data.
                        # However, if the values are locally documented and the documentation is error-free,
                        # we can assume that they are really valid for this language.
                    }
                }
            }
            # Read the global documentation and add features that were not documented locally.
            my @features = keys(%{$docfeats->{gdocs}});
            foreach my $f (@features)
            {
                # Skip globally documented features that have local documentation (even if with errors).
                next if(exists($data{$lcode}{$f}));
                # Type is 'universal' or 'lspec'.
                if(exists($universal{$f}))
                {
                    $data{$lcode}{$f}{type} = 'universal';
                    # This is global documentation of universal feature, thus all values are universal.
                    $data{$lcode}{$f}{uvalues} = $docfeats->{gdocs}{$f}{values};
                    $data{$lcode}{$f}{lvalues} = [];
                    $data{$lcode}{$f}{evalues} = [];
                }
                else
                {
                    $data{$lcode}{$f}{type} = 'lspec';
                    $data{$lcode}{$f}{uvalues} = [];
                    # This is global documentation but the feature is not universal, thus we allow only
                    # those values that were declared in tools/data (if they are mentioned in the documentation).
                    my @lvalues = ();
                    if(exists($declfeats->{$lcode}))
                    {
                        foreach my $v (@{$docfeats->{gdocs}{$f}{values}})
                        {
                            my $fv = "$f=$v";
                            if(grep {$_ eq $fv} (@{$declfeats->{$lcode}}))
                            {
                                push(@lvalues, $v);
                            }
                        }
                    }
                    $data{$lcode}{$f}{lvalues} = \@lvalues;
                    $data{$lcode}{$f}{evalues} = [];
                }
                # Documentation can be 'global', 'local', 'gerror', 'lerror'.
                if(scalar(@{$docfeats->{gdocs}{$f}{errors}}) > 0)
                {
                    $data{$lcode}{$f}{doc} = 'gerror';
                    $data{$lcode}{$f}{errors} = $docfeats->{gdocs}{$f}{errors};
                }
                else
                {
                    $data{$lcode}{$f}{doc} = 'global';
                    # The feature is permitted in this language if it is universal or at least one of its documented values was declared in tools/data.
                    $data{$lcode}{$f}{permitted} = $data{$lcode}{$f}{type} eq 'universal' || scalar(@{$data{$lcode}{$f}{lvalues}}) > 0;
                }
            }
            # Save features that were declared in tools/data but are not documented and thus not permitted.
            if(exists($declfeats->{$lcode}))
            {
                my @fvs = @{$declfeats->{$lcode}};
                foreach my $fv (@fvs)
                {
                    if($fv =~ m/^(.+)=(.+)$/)
                    {
                        my $f = $1;
                        my $v = $2;
                        if(exists($data{$lcode}{$f}))
                        {
                            my $fdata = $data{$lcode}{$f};
                            my @known = (@{$fdata->{uvalues}}, @{$fdata->{lvalues}}, @{$fdata->{evalues}});
                            if(!grep {$_ eq $v} (@known))
                            {
                                # evalues will be list of extra values that were declared but not documented and thus not permitted
                                push(@{$fdata->{evalues}}, $v);
                            }
                        }
                        else
                        {
                            $data{$lcode}{$f}{type} = 'lspec';
                            $data{$lcode}{$f}{doc} = 'none';
                            $data{$lcode}{$f}{permitted} = 0;
                            $data{$lcode}{$f}{uvalues} = [];
                            $data{$lcode}{$f}{lvalues} = [];
                            $data{$lcode}{$f}{evalues} = [];
                            push(@{$data{$lcode}{$f}{evalues}}, $v);
                        }
                    }
                    else
                    {
                        confess("Cannot parse declared feature-value '$fv'");
                    }
                }
            }
            # Check the feature values actually used in the treebank data.
            # Remove unused values from the permitted features.
            # Revoke the permission of the feature if no values remain.
            # Aggregate feature-value pairs over all UPOS categories.
            my %dfall;
            if(exists($datafeats->{$lcode}))
            {
                foreach my $u (keys(%{$datafeats->{$lcode}}))
                {
                    foreach my $f (keys(%{$datafeats->{$lcode}{$u}}))
                    {
                        foreach my $v (keys(%{$datafeats->{$lcode}{$u}{$f}}))
                        {
                            $dfall{$f}{$v}++;
                            # Make the UPOS-specific statistics of features available in the combined database.
                            # $datafeats may contain feature values that are not valid according to the current rules (i.e., they are not documented).
                            # Do not add such feature values to the 'byupos' hash. Discard them.
                            if(exists($data{$lcode}{$f}) && grep {$_ eq $v} (@{$data{$lcode}{$f}{uvalues}}, @{$data{$lcode}{$f}{lvalues}}))
                            {
                                $data{$lcode}{$f}{byupos}{$u}{$v} = $datafeats->{$lcode}{$u}{$f}{$v};
                            }
                        }
                    }
                }
            }
            # Check the features we permitted before.
            foreach my $f (keys(%{$data{$lcode}}))
            {
                # There are boolean universal features that do not depend on the language.
                # Always allow them even if they have not been used in the data so far.
                next if($f =~ m/^(Abbr|Foreign|Typo)$/);
                if($data{$lcode}{$f}{permitted})
                {
                    my @values = @{$data{$lcode}{$f}{uvalues}};
                    $data{$lcode}{$f}{uvalues} = [];
                    $data{$lcode}{$f}{unused_uvalues} = [];
                    foreach my $v (@values)
                    {
                        if(exists($dfall{$f}{$v}))
                        {
                            push(@{$data{$lcode}{$f}{uvalues}}, $v);
                        }
                        else
                        {
                            push(@{$data{$lcode}{$f}{unused_uvalues}}, $v);
                        }
                    }
                    @values = @{$data{$lcode}{$f}{lvalues}};
                    $data{$lcode}{$f}{lvalues} = [];
                    $data{$lcode}{$f}{unused_lvalues} = [];
                    foreach my $v (@values)
                    {
                        if(exists($dfall{$f}{$v}))
                        {
                            push(@{$data{$lcode}{$f}{lvalues}}, $v);
                        }
                        else
                        {
                            push(@{$data{$lcode}{$f}{unused_lvalues}}, $v);
                        }
                    }
                    my $n = scalar(@{$data{$lcode}{$f}{uvalues}}) + scalar(@{$data{$lcode}{$f}{lvalues}});
                    if($n==0)
                    {
                        $data{$lcode}{$f}{permitted} = 0;
                    }
                }
            }
        }
    }
    else
    {
        confess("No documented features found in the JSON file");
    }
    ###!!! Temporary!
    #write_data_json(\%data, "$path/feats.json");
    return %data;
}



#------------------------------------------------------------------------------
# Dumps the data as a JSON file.
#------------------------------------------------------------------------------
sub write_data_json
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
                    $ajson .= join(', ', map {'"'.escape_json_string($_).'"'} (@{$data->{$lcode}{$f}{$array}}));
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
