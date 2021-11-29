import six
assert six.PY3, "Run me with Python3"

import argparse
import sys
import re
import json
import os
import yaml



CONLLU_COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(10)

def trees(inp):
    """
    `inp` object yielding lines

    Yields the input a tree at a time.
    """
    comments=[] #List of comment lines to go with the current tree
    lines=[] #List of token/word lines of the current tree
    for line_counter, line in enumerate(inp):
        line=line.rstrip()
        if not line: #empty line
            if lines: #Sentence done, yield. Skip otherwise.
                yield comments, lines
                comments=[]
                lines=[]
        elif line[0]=="#":
            comments.append(line)
        else:
            cols=line.split("\t")
            assert len(cols)==CONLLU_COLCOUNT
            lines.append(cols)
    else: #end of file
        if comments or lines: #Looks like a forgotten empty line at the end of the file, well, okay...
            yield comments, lines


### Mostly stolen from conllu-stats.py
class TreebankInfo:

    """
    Everything we will ever know about this treebank
    """

    def __init__(self):
        self.token_count=0
        self.word_count=0
        self.tree_count=0
        self.words_with_lemma_count=0
        self.words_with_deps_count=0
        self.words_not_underscore=0
        self.f_val_counter={} #key:f=val  value: count
        self.deprel_counter={} #key:deprel value: count
        self.readme_data_raw={} #raw key-value pairs from readme
        self.language_name=None
        self.treebank_code=None #xxx
        self.treebank_lcode_code=None #cs_xxx
        self.language_code=None #cs
        self.score=0 # <0;1> # read eval.log from master branch
        self.stars=0 # 0 | 0.5 | ... | 4.5 | 5

    def count_cols(self,cols):
        if cols[ID].isdigit() or "." in cols[ID]: #word or empty word
            self.word_count+=1
            self.token_count+=1 #every word is also a one-word token
        else: #token
            b,e=cols[ID].split("-")
            b,e=int(b),int(e)
            self.token_count-=e-b #every word is counted as a token, so subtract all but one to offset for that
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



    def count(self,f_name):
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

# Documentation status: complete
# Data source: semi-automatic
# Data available since: UD v1.0
# License: CC BY-SA 4.0
# Genre: news wiki blog legal fiction grammar-examples
# Contributors: Ginter, Filip; Kanerva, Jenna; Laippala, Veronika; Missilä, Anna; Ojala, Stina; Pyysalo, Sampo
# Contact: figint@utu.fi, jmnybl@utu.fi

    def read_readme(self,f_name):
        metadata_keys=["Documentation status", "Data source", "Data available since", "License", "Genre", "Contributors", "Contact", "Lemmas", "UPOS", "XPOS", "Features", "Relations", "Contributing"]
        metadata_re=re.compile(r"^(%s)\s*:\s*(.*)$"%("|".join(metadata_keys)),re.I)

        in_summary=False
        summary=[]
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

        #metadata_dict gets remembered in self.readme_data_raw

        meta={"license":("unknown","unknown"), "avail":"unknown", "genre":[], "contributors":[], "contact":[], "summary":("\n".join(summary)).strip()} #Processed meta
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
        meta["source"]["all"]=metadata_dict.get("data source","unknown")
        meta["source"]["lemmas"]=metadata_dict.get("Lemmas","unknown")
        meta["source"]["upos"]=metadata_dict.get("UPOS","unknown")
        meta["source"]["xpos"]=metadata_dict.get("XPOS","unknown")
        meta["source"]["features"]=metadata_dict.get("Features","unknown")
        meta["source"]["relations"]=metadata_dict.get("Relations","unknown")
        meta["where_contribute"]=metadata_dict.get("Contributing","unknown")
        self.meta=meta

    def read_eval(self,f_name):
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



    def as_json(self,args=None):
        final={}
        final["counts"]={"token":self.token_count, "word":self.word_count, "tree":self.tree_count, "word_w_lemma":self.words_with_lemma_count, "word_w_deps":self.words_with_deps_count, "fvals": self.f_val_counter, "deprels": self.deprel_counter, "word_not_underscore":self.words_not_underscore}
        final["language_name"]=self.language_name
        final["treebank_code"]=self.treebank_code
        final["treebank_lcode_code"]=self.treebank_lcode_code
        final["language_code"]=self.language_code
        final["repo_name"]=self.repo_name
        final["repo_branch"]=self.repo_branch
        final["readme_file"]=self.readme_file
        final["meta"]=self.meta
        final["score"]=self.score
        final["stars"]=self.stars
        if args and args.exclude_counts_from_json:
            final["counts"]={}
        return json.dumps(final,indent=4,sort_keys=True)


if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for background stats generation. Assumes a validated input. This is used to generate a json which holds all vital data for the index page generation and the like. Rerun whenever anything changes in data repo.')
    opt_parser.add_argument('input', nargs='+', help='Input conllu files')
    opt_parser.add_argument('--readme-dir', help='Directory to look for a readme file to go with this data')
    opt_parser.add_argument('--repo-name',help="Something like UD_Finnish-TDT, used to guess language name and treebank suffix code")
    opt_parser.add_argument('--repo-branch',help='master|dev')
    opt_parser.add_argument('--codes-flags',help="Language code and flag file")
    opt_parser.add_argument("--json",default=False,action="store_true",help="Dump stats as JSON")
    opt_parser.add_argument("--exclude-counts-from-json",default=False,action="store_true",help="Exclude counts from JSON. Only needed for debugging really.")
    args=opt_parser.parse_args()

    stats=TreebankInfo()



    if args.readme_dir:
        for dn in ("README.txt","README.md"):
            if os.path.exists(os.path.join(args.readme_dir,dn)):
                stats.read_readme(os.path.join(args.readme_dir,dn))
                stats.readme_file=dn
                break
        if os.path.exists(os.path.join(args.readme_dir,"eval.log")):
            stats.read_eval(os.path.join(args.readme_dir,"eval.log"))

    if args.repo_name:
        stats.repo_name=args.repo_name
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
                codes_flags=yaml.load(f)
            stats.language_code=codes_flags[stats.language_name]["lcode"]
            stats.treebank_lcode_code=stats.language_code
            if stats.treebank_code:
                stats.treebank_lcode_code+="_"+stats.treebank_code.lower()
        # A dirty hack. Some language names are too long to fit nicely in the
        # table on the UD intro page. Shorten them. Only do it now when we have
        # used them to access the language code and flag.
        if stats.language_name == 'Western Sierra Puebla Nahuatl':
            stats.language_name = 'Western S.P. Nahuatl'

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
