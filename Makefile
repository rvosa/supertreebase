# this makefile contains the steps needed for running a supertree analysis over the contents
# of TreeBASE. The 10 targets are as follows:
# 1.  sitemap        = Download the TreeBASE sitemap
# 2.  purls          = Parse the sitemap, extract all study URIs
# 3.  studies        = For each study URI, fetch the study, i.e. *.url => *.xml
# 4.  tb2mrp_taxa    = For each tree block in each study, generate an MRP matrix, i.e. *.xml => *.txt
# 5.  taxa           = Make a list of all taxa in the MRP matrices, i.e. taxa.txt
# 6.  species        = Collapse subspecies and expand higher taxa to species, i.e. taxa.txt => species.txt
# 7.  ncbimrp        = Write MRP matrix from NCBI taxonomy using species list, i.e. species.txt => ncbi.dat
# 8.  tb2mrp_species = Normalize TreeBASE MRP matrices to species level, i.e. *.txt => *.dat
# 9.  Convert TreeBASE MRP matrices to TNT file inclusion command and data matrix one file per tree block, i.e. *.dat => *.run, *.tnt, nchar.txt
# 10. Create meta-file inclusion script for TNT

# eukaryotes
ROOTID=2759
PERL=perl
EXTRACT=unzip
ARCH=zip
MKPATH=mkdir -p
RM_RF=rm -rf
SCRIPT=script
CURL=curl
CAT=cat
ECHO=echo
DATA=data
VERBOSITY=-v -v -v
MRPDIR=$(DATA)/mrp
MRPTABLE=$(MRPDIR)/combined.dat
TAXDMP=taxdmp
TAXDMPDIR=$(DATA)/$(TAXDMP)
TAXDMPTMP=$(TAXDMPDIR)/tmp
TAXDMPARCH=$(TAXDMPDIR)/$(TAXDMP).$(ARCH)
TAXDMPURL=ftp.ncbi.nlm.nih.gov/pub/taxonomy/$(TAXDMP).$(ARCH)
NCBIMRP=$(MRPDIR)/ncbi.dat
NCBINODES=$(TAXDMPDIR)/nodes.dmp
NCBINAMES=$(TAXDMPDIR)/names.dmp
NCBIFILES=$(NCBINODES) $(NCBINAMES)
TB2STUDYPURLS=$(wildcard $(TB2DATA)/*.url)
TB2STUDYFILES=$(patsubst %.url,%.xml,$(TB2STUDYPURLS))
TB2MRPFILES=$(patsubst %.xml,%.txt,$(TB2STUDYFILES))
TB2NRMLMRP=$(patsubst %.xml,%.dat,$(TB2STUDYFILES))
TB2CLASSES=$(patsubst %.xml,%.class,$(TB2STUDYFILES))
TNTCOMMANDS=$(patsubst %.dat,%.run,$(TB2NRMLMRP))
TB2DATA=$(DATA)/treebase
TB2SITEMAP=sitemap.xml
TB2SITEMAPXML=$(TB2DATA)/$(TB2SITEMAP)
TB2SITEMAPURL=http://treebase.org/treebase-web/$(TB2SITEMAP)
TB2TAXA=$(TB2DATA)/taxa.txt
TB2SPECIES=$(TB2DATA)/species.txt
TB2NCHAR=$(TB2DATA)/nchar.txt
TNTSCRIPT=$(TB2DATA)/tntscript.runall

.PHONY : 

# fetch the TreeBASE site map
$(TB2SITEMAPXML) :
	$(MKPATH) $(TB2DATA)
	$(RM_RF) $(TB2SITEMAPXML)
	$(CURL) -o $(TB2SITEMAPXML) $(TB2SITEMAPURL)
sitemap : $(TB2SITEMAPXML)
sitemap_clean : 
	$(RM_RF) $(TB2SITEMAPXML)

# turn the study URLs in the site map into local *.url files with PURLs
purls : $(TB2SITEMAPXML)
	$(PERL) $(SCRIPT)/make_tb2_urls.pl -i $(TB2SITEMAPXML) -o $(TB2DATA)
purls_clean : 
	$(RM_RF) $(TB2DATA)/*.url

# fetch the studies
$(TB2STUDYFILES) : %.xml : %.url
	$(CURL) -L -o $@ `cat $<`
studies : $(TB2STUDYFILES)
studies_clean : 
	$(RM_RF) $(TB2STUDYFILES)

# extract the NCBI classes
$(TB2CLASSES) : %.class : %.xml
	$(PERL) $(SCRIPT)/getclass.pl -nodes $(NCBINODES) -names $(NCBINAMES) -taxa $(TAXDMPDIR) -i $< $(VERBOSITY) > $@
classes : $(TB2CLASSES)
classes_clean :
	$(RM_RF) $(TB2CLASSES)

# make TreeBASE MRP matrices
$(TB2MRPFILES) : %.txt : %.xml
	$(PERL) $(SCRIPT)/make_tb2_mrp.pl -i $< $(VERBOSITY) > $@
tb2mrp_taxa : $(TB2MRPFILES)
tb2mrp_taxa_clean : 
	$(RM_RF) $(TB2MRPFILES)

# create list of unique taxon IDs with occurrence counts
$(TB2TAXA) : $(TB2MRPFILES)
	cat $(TB2MRPFILES) | cut -f 2 | sort | uniq -c > $@
taxa : $(TB2TAXA)
taxa_clean : 
	$(RM_RF) $(TB2TAXA)

# make species-level list from TreeBASE taxon IDs
$(TB2SPECIES) : $(TB2TAXA) $(NCBIFILES)
	$(PERL) $(SCRIPT)/make_species_list.pl -taxa `pwd`/$(TB2TAXA) -nodes `pwd`/$(NCBINODES) -names `pwd`/$(NCBINAMES) -dir `pwd`/$(TAXDMPTMP) $(VERBOSITY) > $@
species : $(TB2SPECIES)
species_clean : 
	$(RM_RF) $(TB2SPECIES)

# make MRP tables with normalized species and ambiguity codes for polyphyly
$(TB2NRMLMRP) : %.dat : %.txt
	$(PERL) $(SCRIPT)/normalize_tb2_mrp.pl -i $< -s $(TB2SPECIES) $(VERBOSITY) > $@
tb2mrp_species : $(TB2NRMLMRP)
tb2mrp_species_clean : 
	$(RM_RF) $(TB2NRMLMRP)

# download taxdmp archive
$(NCBIFILES) :
	$(MKPATH) $(TAXDMPDIR)
	$(CURL) -o $(TAXDMPARCH) $(TAXDMPURL)
	cd $(TAXDMPDIR) && $(EXTRACT) $(TAXDMP).$(ARCH) && cd -
ncbi : $(NCBIFILES)
ncbi_clean : 
	$(RM_RF) $(TAXDMPDIR)

# make NCBI MRP matrix
$(NCBIMRP) : $(NCBIFILES) $(TB2SPECIES)
	$(MKPATH) $(MRPDIR) $(TAXDMPTMP)
	$(PERL) $(SCRIPT)/make_ncbi_mrp.pl -species $(TB2SPECIES) -nodes $(NCBINODES) -names $(NCBINAMES) -dir $(TAXDMPTMP) $(VERBOSITY) > $@
ncbimrp : $(NCBIMRP)
ncbimrp_clean : 
	$(RM_RF) $(NCBIMRP)

# make tnt file inclusion commands and single file with nchar for each treeblock
$(TNTCOMMANDS) : %.run : %.dat
	$(PERL) $(SCRIPT)/make_tnt.pl -i $< $(VERBOSITY) > $@ 2>> $(TB2NCHAR)
tntdata : $(TNTCOMMANDS)
tntdata_clean : 
	$(RM_RF) $(TNTCOMMANDS) $(TB2NCHAR) $(TB2DATA)/*.tnt

# make the master tnt script
$(TNTSCRIPT) : $(TNTCOMMANDS)
	$(PERL) $(SCRIPT)/make_tnt_script.pl -n $(TB2NCHAR) -s $(TB2SPECIES) $(VERBOSITY) > $@
	$(CAT) $(TNTCOMMANDS) >> $@
	$(ECHO) 'proc/;' >> $@
tntscript : $(TNTSCRIPT)
tntscript_clean : 
	$(RM_RF) $(TNTSCRIPT)
