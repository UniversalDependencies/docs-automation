# Common functions for the CGI scripts that handle registration of UD
# validation data (specify_auxiliary.pl, specify_feature.pl etc.)
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

package common;

use Carp;
use utf8;



#------------------------------------------------------------------------------
# Generates the header and beginning of the body of the HTML page. Returns it
# as a string.
#------------------------------------------------------------------------------
sub generate_html_start
{
    my $titlepart = shift; # auxiliaries | features | ...
    my $html = <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify $titlepart in UD</title>
  <link rel="icon" href="https://universaldependencies.org/logos/logo-ud.png" type="image/png">
  <style type="text/css">
    img {border: none;}
    img.flag {
      vertical-align: middle;
      border: solid grey 1px;
      height: 1em;
    }
  </style>
</head>
<body>
  <p style="position: absolute; right: 10px; font-size:0.8em">
    <a href="specify_auxiliary.pl">a</a>
    <a href="specify_feature.pl">f</a>
    <a href="specify_deprel.pl">d</a>
    <a href="specify_edeprel.pl">e</a>
    <a href="specify_token_with_space.pl">t</a>
  </p>
EOF
    ;
    return $html;
}



1;
