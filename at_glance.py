#! /usr/bin/env python3
# Original code (2017) by Filip Ginter.
# Later modifications by Dan Zeman.
import six
assert six.PY3, "Run me with Python3"
import jinja2
import json
import argparse
import yaml
from yaml.loader import SafeLoader
import sys
import functools
import os.path
import re

def sum_dicts(dicts):
    #dicts is a bunch of dicts with int values, for all keys sums all values
    res={}
    for k in dicts[0]:
        if isinstance(dicts[0][k],int):
            res[k]=sum(d[k] for d in dicts)
    return res

def thousand_sep_filter(val,use_k=False):
    """
    Used from the template to produce thousand-separated numbers, optionally with "K" for thousands.
    """
    if not use_k:
        return "{:,}".format(val)
    else:
        if val==0:
            return "-"
        elif val<1000:
            return "<1K"
        else:
            return "{:,}K".format(val//1000)

def tag_filter(counts):
    """
    Used from the template to produce the L-F-E tags.
    """
    result=""
    empty_span='<span class="tagspan"></span>'
    #tag_span='<span class="tagspan"><span class="hint--top hint--info" data-hint="%s"><img class="propertylogo" src="logos/%s.svg" /></span></span>'
    tag_span='<span class="tagspan"><span class="hint--top hint--info" data-hint="%s">%s</span></span>'
    if counts["word"] and counts["word_w_lemma"]/counts["word"]>0.1:
        #result+=tag_span%("Lemmas","L")
        result+=tag_span%("Lemmas","Ⓛ")
    else:
        result+=empty_span
    if len(counts["fvals"])>5:
        #result+=tag_span%("Features","F")
        result+=tag_span%("Features","Ⓕ")
    else:
        result+=empty_span
    if counts["word"] and counts["word_w_deps"]>10:
        #result+=tag_span%("Enhanced dependencies","D")
        result+=tag_span%("Enhanced dependencies","Ⓔ")
    else:
        result+=empty_span
    return result

def genre_filter(genres, genre_symbols={}):
    """
    Used from the template to produce the genre symbols.
    """
    genres = sorted(set(genres))
    span = '<i class="fa fa-%s"></i>'
    symbols = ' '.join(genres)
    spans = ''.join(span%genre_symbols.get(g,"file-o") for g in genres)
    return '<span class="hint--top hint--info" data-hint="%s">%s</span>'%(symbols,spans)

def family_filter(language_family_genus):
    """
    Used from the template to produce language family with genre if present.
    """
    classification = language_family_genus[0]
    if len(language_family_genus) > 1 and language_family_genus[1]:
        # Shorten genera that are too long for the accordion.
        genus = language_family_genus[1]
        genus = re.sub(r'^Central Malayo-Polynesian$', r'Malayo-Polynesian', genus)
        genus = re.sub(r' Pama-Nyungan$', r'', genus) # e.g. Western Pama-Nyungan
        classification += ', ' + genus
    return classification

def license_filter(lic):
    """Used from the template to produce the license logo"""
    lic_abbr,lic_name=lic # something like BY-SA, CC BY-SA 4.0 unported
    if lic_abbr == "GNU":
        logo_file = "gpl"
    elif lic_name.startswith("CC0"):
        logo_file = "cc-zero"
    elif lic_name.startswith("CC"):
        logo_file = lic_abbr.lower()
    elif lic == "LGPLLR":
        logo_file = "LGPLLR"
    else:
        logo_file = None
    if logo_file:
        return '<span class="hint--top hint--info" data-hint="%s"><img class="license" src="logos/%s.svg" /></span>'%(lic_name,logo_file)
    else:
        return '<span class="hint--top hint--info" data-hint="%s">?</span>'%(lic_name)

def contributor_filter(contributors):
    cont_list=[]
    for c in contributors:
        parts=c.split(", ",1)
        if len(parts)==2:
            cont_list.append(parts[1]+" "+parts[0])
        else:
            cont_list.append(parts[0])
    return ", ".join(cont_list)

def stars_filter(scorestars):
    """
    Used from the template to produce stars rating the treebank.
    Takes a pair of floats (score,stars).
    """
    score=scorestars[0]
    stars=scorestars[1]
    return '<span class="hint--top hint--info" data-hint="Size/quality/diversity score=%f"><img src="/img/stars%02d.png" style="max-height:1em; vertical-align:middle" /></span>'%(score,stars*10)



if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Generates the index page table')
    opt_parser.add_argument('--codes-flags', help="YAML file with language codes and flags.")
    opt_parser.add_argument('--releases', help="JSON file with release descriptions.")
    opt_parser.add_argument('--genre-symbols', help="JSON file with genre symbols.")
    opt_parser.add_argument('--subset', default=None, action='store', help="Default: print all. Optionally select one of 'current', 'sapling', 'retired'.")
    opt_parser.add_argument('--docs-dir', default="docs-src", action="store", help="Docs dir so we can check for existence of files. Default '%(default)s'.")
    opt_parser.add_argument('input', nargs='+', help='Input corpus stat json files')
    args=opt_parser.parse_args()

    with open(args.codes_flags) as f:
        codes_flags = yaml.load(f, Loader=SafeLoader)
    # Get the list of used genera for each language family.
    # We will only display the genus if we have languages from multiple genera of that family.
    family_genera = {}
    for l in codes_flags:
        if not codes_flags[l]['family'] in family_genera:
            family_genera[codes_flags[l]['family']] = {}
        if 'genus' in codes_flags[l]:
            family_genera[codes_flags[l]['family']][codes_flags[l]['genus']] = True
    # Replace the dictionary of genera with the number of genera.
    for f in family_genera:
        family_genera[f] = len(list(family_genera[f]))

    with open(args.releases) as f:
        loaded_json = json.load(f)
        releases = loaded_json['releases']
        renames = loaded_json['renamed_after_release']
    # The database of releases is a dictionary but the keys should be already sorted.
    release_numbers = [r for r in releases.keys()]
    last_release_number = release_numbers[-1]
    print("Last release number = %s" % last_release_number, file=sys.stderr)
    last_release_treebanks = releases[last_release_number]['treebanks']
    # If a treebank was renamed since the last release, take the new name.
    if last_release_number in renames:
        rename_dict = {}
        for rename in renames[last_release_number]:
            rename_dict[rename[0]] = rename[1]
            print(f"Renamed {rename[0]} to {rename[1]}", file=sys.stderr)
        last_release_treebanks_renamed = [rename_dict[x] if x in rename_dict else x for x in last_release_treebanks]
        last_release_treebanks = last_release_treebanks_renamed

    with open(args.genre_symbols) as f:
        genre_symbols = json.load(f)

    t_env = jinja2.Environment(loader=jinja2.PackageLoader('at_glance', 'templates'), autoescape=True)
    t_env.filters['tsepk'] = thousand_sep_filter
    t_env.filters['tag_filter'] = tag_filter
    t_env.filters['genre_filter'] = functools.partial(genre_filter,genre_symbols=genre_symbols)
    t_env.filters['family_filter'] = family_filter
    t_env.filters['license_filter'] = license_filter
    t_env.filters['contributor_filter'] = contributor_filter
    t_env.filters['stars_filter'] = stars_filter

    tbanks={} # language -> [tbank, tbank, ...]
    for f_name in args.input:
        try:
            with open(f_name) as f:
                tbank = json.load(f)
                tbanks.setdefault(tbank['language_name'], []).append(tbank)
        except:
            print("Whoa, couldn't load", f_name, file=sys.stderr)

    lang_template = t_env.get_template('language.md')
    for lang, lang_tbanks in sorted(tbanks.items()):
        # Select the required subset of treebanks. If no subset is required, all treebanks will be output.
        if args.subset == 'current':
            lang_tbanks = [t for t in lang_tbanks if t['repo_name'] in last_release_treebanks]
        elif args.subset == 'sapling':
            lang_tbanks = [t for t in lang_tbanks if not t['first_release'] and not t['repo_name'] in last_release_treebanks]
        elif args.subset == 'retired':
            lang_tbanks = [t for t in lang_tbanks if t['first_release'] and not t['repo_name'] in last_release_treebanks]
        if len(lang_tbanks)==0:
            continue
        sum_counts = sum_dicts(list(t['counts'] for t in lang_tbanks))
        union_genres = set()
        for t in lang_tbanks:
            union_genres |= set(t['meta']['genre'])
        union_genres = list(union_genres)
        # Sort treebanks by evaluation score (this is new) or by size (this is old; comment one of the two lines):
        #lang_tbanks.sort(key=lambda tb: tb["counts"]["word"],reverse=True)
        lang_tbanks.sort(key=lambda tb: tb['score'], reverse=True)
        language_code = codes_flags[lang]['lcode']
        language_name_short = lang_tbanks[0]['language_name_short'] if len(lang_tbanks)>0 else lang
        if os.path.exists(os.path.join(args.docs_dir, '_'+language_code, 'index.md')):
            language_hub = 'index.md'
        else:
            language_hub = None
        if os.path.exists(os.path.join(args.docs_dir, 'treebanks', language_code+'-comparison.md')):
            tbank_comparison = language_code+'-comparison.html'
        else:
            tbank_comparison = None
        language_genus = None
        if 'genus' in codes_flags[lang] and family_genera[codes_flags[lang]['family']] > 1:
            language_genus = codes_flags[lang]['genus']
        r = lang_template.render(
            flag=codes_flags[lang]['flag'],
            language_name=lang,
            language_name_short=language_name_short,
            language_code=language_code,
            language_hub=language_hub,
            tbank_comparison=tbank_comparison,
            counts=sum_counts,
            treebanks=lang_tbanks,
            genres=union_genres,
            language_family=codes_flags[lang]['family'],
            language_genus=language_genus)
        print(r)
