#! /usr/bin/env python3
# Original code (2017) by Filip Ginter.
# Later modifications by Dan Zeman.
import six
assert six.PY3, "Run me with Python3"

import argparse
import sys
import re
import json
import os
import yaml
from yaml.loader import SafeLoader
import logging



CONLLU_COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(10)

def trees(inp):
    """
    `inp` object yielding lines

    Yields the input a tree at a time.
    """
    comments=[] # List of comment lines to go with the current tree
    lines=[] # List of token/word lines of the current tree
    for line_counter, line in enumerate(inp):
        line=line.rstrip()
        if not line: # empty line
            if lines: # Sentence done, yield. Skip otherwise.
                yield comments, lines
                comments=[]
                lines=[]
        elif line[0]=="#":
            comments.append(line)
        else:
            cols=line.split("\t")
            assert len(cols)==CONLLU_COLCOUNT
            lines.append(cols)
    else: # end of file
        if comments or lines: # Looks like a forgotten empty line at the end of the file, well, okay...
            yield comments, lines


class RelNum(object):
    """
    A class for release numbers. It allows for the desired comparison and
    ordering of release numbers.
    """
    def __init__(self, obj, *args):
        """
        We assume that obj is a string that looks like a decimal number.
        """
        self.obj = str(obj)
        if not re.match(r'^\d+\.\d+$', self.obj):
            logging.fatal("'%s' does not look like a release number" % (self.obj))
    def __lt__(self, other):
        return self.cmp(self.obj, other.obj) < 0
    def __gt__(self, other):
        return self.cmp(self.obj, other.obj) > 0
    def __eq__(self, other):
        return self.cmp(self.obj, other.obj) == 0
    def __le__(self, other):
        return self.cmp(self.obj, other.obj) <= 0
    def __ge__(self, other):
        return self.cmp(self.obj, other.obj) >= 0
    def __ne__(self, other):
        return self.cmp(self.obj, other.obj) != 0
    def cmp(self, a, b):
        """
        Compares UD release numbers. They must be strings, not floats!
        Major and minor numbers are taken separately, i.e., 2.10 > 2.2.
        """
        if not re.match(r'^\d+\.\d+$', a):
            logging.fatal("'%s' does not look like a release number" % (a))
        if not re.match(r'^\d+\.\d+$', b):
            logging.fatal("'%s' does not look like a release number" % (b))
        amajs, amins = a.split('.')
        bmajs, bmins = b.split('.')
        amaj = int(amajs)
        amin = int(amins)
        bmaj = int(bmajs)
        bmin = int(bmins)
        if amaj > bmaj:
            return 1
        elif amaj < bmaj:
            return -1
        else:
            if amin > bmin:
                return 1
            elif amin < bmin:
                return -1
            else:
                return 0



class TreebankInfo:

    """
    Everything we will ever know about this treebank
    """

    def __init__(self):
        self.tree_count=0
        self.token_count=0 # surface tokens (some may cover multiple words)
        self.word_count=0 # morphosyntactic words, i.e., non-empty nodes
        self.node_count=0 # all nodes including empty nodes in enhanced graphs
        self.words_with_lemma_count=0
        self.words_with_deps_count=0
        self.words_not_underscore=0
        self.f_val_counter={} # key:f=val  value: count
        self.deprel_counter={} # key:deprel value: count
        self.readme_data_raw={} # raw key-value pairs from readme
        self.language_name=None
        self.language_name_short=None
        self.treebank_code=None # xxx
        self.treebank_lcode_code=None # cs_xxx
        self.language_code=None # cs
        self.first_release=None
        self.score=0 # <0;1> # read eval.log from master branch
        self.stars=0 # 0 | 0.5 | ... | 4.5 | 5


    def count_cols(self,cols):
        if '.' in cols[ID]: # empty node
            self.node_count+=1
        elif cols[ID].isdigit(): # non-empty morphosyntactic word
            self.node_count+=1
            self.word_count+=1
            self.token_count+=1 # normal word is also a one-word token, multiword tokens will be compensated below
        else: # multiword token
            b,e=cols[ID].split('-')
            b,e=int(b),int(e)
            self.token_count-=e-b # every word is counted as a token, so subtract all but one to offset for that
        # Below we count "words_with_lemma" and similar, but they are not
        # words in the sense of the word_count above. They can be multiword
        # tokens or empty nodes.
        if cols[FORM]!="_":
            self.words_not_underscore+=1
        if cols[LEMMA]!="_" or (cols[LEMMA]=="_" and cols[FORM]=="_"):
            self.words_with_lemma_count+=1
        if cols[UPOS]!="_":
            self.f_val_counter["UPOS="+cols[UPOS]]=self.f_val_counter.get("UPOS="+cols[UPOS],0)+1
        if cols[FEATS]!=u"_":
            for cat_is_vals in cols[FEATS].split(u"|"):
                cat,vals=cat_is_vals.split(u"=",1)
                for val in vals.split(u","):
                    self.f_val_counter[cat+u"="+val]=self.f_val_counter.get(cat+u"="+val,0)+1
        if cols[DEPREL]!=u"_":
            self.deprel_counter[cols[DEPREL]]=self.deprel_counter.get(cols[DEPREL],0)+1
        if cols[DEPS]!=u"_":
            self.words_with_deps_count+=1
            for head_and_deprel in cols[DEPS].split(u"|"):
                head,deprel=head_and_deprel.split(u":",1)
                self.deprel_counter[deprel]=self.deprel_counter.get(deprel,0)+1


    def count(self, f_name):
        """f_name is conllu, counts stuff in f_name"""
        try:
            with open(f_name) as f:
                for comments,tree in trees(f):
                    try:
                        self.tree_count+=1
                        for cols in tree:
                            self.count_cols(cols)
                    except:
                        print("Error in tree\n", "\n".join(comments), file=sys.stderr)
                        print("\n".join("\t".join(cols) for cols in tree), file=sys.stderr)
        except:
            print("Giving up on",f_name,file=sys.stderr)


    def get_first_release(self, releases):
        """
        Reads the list of official UD releases from docs-automation/valdan/releases.json.
        Returns the number of the release where the treebank appeared for the first time,
        or None if it has not been released yet. This information sometimes differs from
        the README metadata 'Data available since' and it is more reliable here.
        """
        sorted_release_numbers = sorted(releases.keys(), key=RelNum)
        self.first_release = None
        frmap = {}
        for r in sorted_release_numbers:
            # If an old treebank is released under a new name, fetch its real first appearance.
            if 'renamed' in releases[r]:
                for pair in releases[r]['renamed']:
                    if pair[0] in frmap:
                        frmap[pair[1]] = frmap[pair[0]]
                        if pair[1] == self.repo_name:
                            self.first_release = frmap[pair[1]]
                            return self.first_release
            for t in releases[r]['treebanks']:
                if t == self.repo_name:
                    self.first_release = r
                    return self.first_release
                # Remember the first occurrence of every treebank name because
                # it could be later renamed to what we are looking for.
                if not t in frmap:
                    frmap[t] = r
        return self.first_release


    def read_readme(self, f_name):
        metadata_keys=["Data available since", "License", "Includes text", "Parallel", "Genre", "Lemmas", "UPOS", "XPOS", "Features", "Relations", "Contributors", "Contributing", "Contact"]
        metadata_re=re.compile(r"^(%s)\s*:\s*(.*)$"%("|".join(metadata_keys)),re.I)
        in_summary=False
        summary=[]
        # metadata_dict gets remembered in self.readme_data_raw
        metadata_dict=self.readme_data_raw
        with open(f_name) as f:
            for line in f:
                line=line.strip()
                match=metadata_re.match(line)
                if match:
                    metadata_dict[match.group(1).lower().strip()]=match.group(2).strip()
                    continue
                if re.match(r"^#\s*Summary", line):
                    in_summary=True
                    continue
                if re.match(r"^#(\s|$)",line):
                    in_summary=False
                    continue
                if in_summary:
                    summary.append(line)
        meta={"license":("unknown","unknown"), "avail":"unknown", "genre":[], "contributors":[], "contact":[], "summary":("\n".join(summary)).strip()} # Processed meta
        #license
        if "license" in metadata_dict:
            lic=metadata_dict["license"]
            if lic.startswith("CC"):
                parts=lic.split()
                meta["license"]=(parts[1],lic) #parts[1] is the BY-SA etc part
            elif "GNU" in lic or "GPL" in lic:
                meta["license"]=("GNU",lic)
            else:
                meta["license"]=("unknown",lic)
        if "data available since" in metadata_dict:
            avail=metadata_dict["data available since"]
            match=re.match("^UD v([0-9]+)\.([0-9]+)$", avail)
            if match:
                meta["avail"]=(match.group(1),match.group(2))
            else:
                meta["avail"]="unknown"
        meta["genre"]=list(g for g in metadata_dict.get("genre","").split() if g)
        for c in metadata_dict.get("contributors","").split(";"):
            if c.strip():
                meta["contributors"].append(c.strip())
        for c in metadata_dict.get("contact","").replace(","," ").replace(";"," ").split():
            if c.strip() and c.strip!="email@domain.com":
                meta["contact"].append(c)
        meta["source"]={}
        meta["source"]["text"]=metadata_dict.get("includes text","yes")
        meta["source"]["lemmas"]=metadata_dict.get("lemmas","unknown")
        meta["source"]["upos"]=metadata_dict.get("upos","unknown")
        meta["source"]["xpos"]=metadata_dict.get("xpos","unknown")
        meta["source"]["features"]=metadata_dict.get("features","unknown")
        meta["source"]["relations"]=metadata_dict.get("relations","unknown")
        meta["parallel"]=metadata_dict.get("parallel","no")
        meta["where_contribute"]=metadata_dict.get("contributing","unknown")
        self.meta=meta


    def read_eval(self, f_name):
        self.score=0
        self.stars=0
        with open(f_name) as f:
            result_re=re.compile(r"^UD_\S+\t([-+0-9\.e]+)\t([0-9\.]+)$")
            for line in f:
                line=line.strip()
                match=result_re.match(line)
                if match:
                    self.score=float(match.group(1))
                    self.stars=float(match.group(2))


    def as_json(self, args=None):
        final = {}
        final['counts'] = {
            "tree":self.tree_count,
            "token":self.token_count,
            "word":self.word_count,
            "node":self.node_count,
            "word_w_lemma":self.words_with_lemma_count,
            "word_w_deps":self.words_with_deps_count,
            "fvals": self.f_val_counter,
            "deprels": self.deprel_counter,
            "word_not_underscore":self.words_not_underscore
        }
        final['language_name'] = self.language_name
        final['language_name_short'] = self.language_name_short
        final['treebank_code'] = self.treebank_code
        final['treebank_lcode_code'] = self.treebank_lcode_code
        final['language_code'] = self.language_code
        final['repo_name'] = self.repo_name
        final['repo_branch'] = self.repo_branch
        final['first_release'] = self.first_release
        final['readme_file'] = self.readme_file
        final['meta'] = self.meta
        final['score'] = self.score
        final['stars'] = self.stars
        if args and args.exclude_counts_from_json:
            final['counts'] = {}
        return json.dumps(final, indent=4, sort_keys=True)


if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for background stats generation. Assumes a validated input. This is used to generate a json which holds all vital data for the index page generation and the like. Rerun whenever anything changes in data repo.')
    opt_parser.add_argument('input', nargs='+', help='Input conllu files')
    opt_parser.add_argument('--readme-dir', help='Directory to look for a readme file to go with this data')
    opt_parser.add_argument('--repo-name', help='Something like UD_Finnish-TDT, used to guess language name and treebank suffix code')
    opt_parser.add_argument('--repo-branch', help='master|dev')
    opt_parser.add_argument('--codes-flags', help='Language code and flag file')
    opt_parser.add_argument('--releases', help='JSON file describing previous UD releases')
    opt_parser.add_argument("--json", default=False, action="store_true", help="Dump stats as JSON")
    opt_parser.add_argument("--exclude-counts-from-json",default=False,action="store_true",help="Exclude counts from JSON. Only needed for debugging really.")
    args=opt_parser.parse_args()

    stats=TreebankInfo()

    # We should probably ask whether the --releases option has been provided but we need it always.
    with open(args.releases) as f:
        releases_root = json.load(f)
    releases = releases_root['releases']

    if args.readme_dir:
        for dn in ("README.txt","README.md"):
            if os.path.exists(os.path.join(args.readme_dir,dn)):
                stats.read_readme(os.path.join(args.readme_dir,dn))
                stats.readme_file=dn
                break
        if os.path.exists(os.path.join(args.readme_dir,"eval.log")):
            stats.read_eval(os.path.join(args.readme_dir,"eval.log"))

    if args.repo_name:
        stats.repo_name = args.repo_name
        stats.get_first_release(releases) # needs to know stats.repo_name
        lang_dash_code=re.sub("^UD_","",args.repo_name)
        parts=lang_dash_code.split("-")
        if len(parts)==1: #no code
            stats.language_name=parts[0].replace("_"," ")
            stats.treebank_code=""
        elif len(parts)==2:
            stats.language_name=parts[0].replace("_"," ")
            stats.treebank_code=parts[1]
        else:
            raise ValueError("Multiple-dash in repository name: "+args.repo_name)

        if args.codes_flags:
            with open(args.codes_flags) as f:
                codes_flags=yaml.load(f, Loader=SafeLoader)
            stats.language_code=codes_flags[stats.language_name]["lcode"]
            stats.treebank_lcode_code=stats.language_code
            if stats.treebank_code:
                stats.treebank_lcode_code+="_"+stats.treebank_code.lower()
        # A dirty hack. Some language names are too long to fit nicely in the
        # table on the UD intro page. Shorten them.
        stats.language_name_short = stats.language_name
        if stats.language_name_short == 'Western Sierra Puebla Nahuatl':
            stats.language_name_short = 'Western S.P. Nahuatl'
        if stats.language_name_short == 'Highland Puebla Nahuatl':
            stats.language_name_short = 'Highland P. Nahuatl'

    # We may want to get rid of the argument and test the branch ourselves by calling
    # git branch | grep '*' | sed 's/^\*\s*//'
    if args.repo_branch:
        stats.repo_branch=args.repo_branch

    for f_name in args.input:
        match=re.match(r"^([a-z_]+)-ud-(train|dev|test)(-[a-z]+)?\.conllu$",os.path.basename(f_name))
        if match:
            lang_uscore_code=match.group(1)
            parts=lang_uscore_code.split("_")
            if stats.language_code:
                assert stats.language_code==parts[0], (stats.language_code,parts[0])
            else:
                stats.language_code=parts[0]
        if os.path.exists(f_name):
            stats.count(f_name)

    if args.json:
        print(stats.as_json(args))
