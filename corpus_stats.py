import argparse
import sys
import re

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
        self.f_val_counter={} #key:f=val  value: count
        self.deprel_counter={} #key:deprel value: count
        self.readme_data_raw={} #raw key-value pairs from readme
        self.language=None
        self.treebank_code=None
        self.language_code=None

    def count_cols(self,cols):
        if cols[ID].isdigit() or "." in cols[ID]: #word or empty word
            self.word_count+=1
            self.token_count+=1 #every word is also a one-word token
        else: #token
            b,e=cols[ID].split("-")
            b,e=int(b),int(e)
            self.token_count-=e-b #every word is counted as a token, so subtract all but one to offset for that
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
        with open(f_name) as f:
            for comments,tree in trees(f):
                self.tree_count+=1
                for cols in tree:
                    self.count_cols(cols)
# Documentation status: complete
# Data source: semi-automatic
# Data available since: UD v1.0
# License: CC BY-SA 4.0
# Genre: news wiki blog legal fiction grammar-examples
# Contributors: Ginter, Filip; Kanerva, Jenna; Laippala, Veronika; Missilä, Anna; Ojala, Stina; Pyysalo, Sampo
# Contact: figint@utu.fi, jmnybl@utu.fi

    def read_readme(self,f_name):
        metadata_keys=["Documentation status", "Data source", "Data available since", "License", "Genre", "Contributors", "Contact"]
        metadata_re=re.compile(r"^(%s)\s*:\s*(.*)$"%("|".join(metadata_keys)),re.I)

        metadata_dict=self.readme_data_raw
        with open(f_name) as f:
            for line in f:
                line=line.strip()
                match=metadata_re.match(line)
                if not match:
                    continue
                else:
                    metadata_dict[match.group(1)]=match.group(2)
        #metadata_dict gets remembered in self.readme_data_raw
        


if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for background stats generation. Assumes a validated input.')
    opt_parser.add_argument('input', nargs='+', help='Input conllu files')
    opt_parser.add_argument('--readme', help='UD Readme file to go with this data')
    opt_parser.add_argument('--repo-name',help="Something like UD_Finnish-TDT, used to guess language name and treebank suffix code")
    args=opt_parser.parse_args()
    
    stats=TreebankInfo()

    if args.readme:
        stats.read_readme(args.readme)

    if args.repo_name:
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
        
    for f_name in args.input:
        match=re.match(r"^([a-z_]+)-ud-(train|dev|test)\.conllu$",f_name)
        if match:
            lang_uscore_code=match.group(1)
            parts=lang_uscore_code.split("_")
            if stats.language_code:
                assert stats.language_code==parts[0]
            else:
                stats.language_code=parts[0]
                
        stats.count(f_name)


