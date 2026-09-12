# Smart Boot Manager documentation Makefile
# 
# Copyright (c) Suzhe 2000
#

ifeq ($(INFO_DIR),)
INFO_DIR=	/usr/info
endif

ifeq ($(DOC_DIR),)
DOC_DIR=	/usr/share/doc/btmgr
endif

HTML_DIR=	$(DOC_DIR)/html
OTHER_DOCFILES=	../AUTHORS ../COPYING ../ChangeLog ../CREDITS ../INSTALL ../TODO


USERGUIDE=	user-guide

SGML=		${USERGUIDE}.sgml
HTML=		${USERGUIDE}.html
PS=		${USERGUIDE}.ps
TXT=		${USERGUIDE}.txt
INFO=		${USERGUIDE}.info

USERGUIDE_CZ=	user-guide-cz

SGML_CZ=	${USERGUIDE_CZ}.sgml
HTML_CZ=	${USERGUIDE_CZ}.html
PS_CZ=		${USERGUIDE_CZ}.ps
TXT_CZ=		${USERGUIDE_CZ}.txt
INFO_CZ=	${USERGUIDE_CZ}.info

USERGUIDE_ZH=	user-guide-zh

SGML_ZH=	${USERGUIDE_ZH}.sgml
HTML_ZH=	${USERGUIDE_ZH}.html
TXT_ZH=		${USERGUIDE_ZH}.txt
INFO_ZH=	${USERGUIDE_ZH}.info

all:	${HTML} ${PS} ${TXT} ${INFO} \
	${HTML_CZ} ${PS_CZ} ${TXT_CZ} ${INFO_CZ} \
	${HTML_ZH} ${TXT_ZH} ${INFO_ZH}

${HTML}: ${SGML}
	sgml2html $<
${PS}: ${SGML}
	sgml2latex --output=ps $<
${TXT}: ${SGML}
	sgml2txt --filter $<
${INFO}: ${SGML}
	sgml2info $<

${HTML_CZ}: ${SGML_CZ}
	sgml2html $<
${PS_CZ}: ${SGML_CZ}
	sgml2latex --output=ps $<
${TXT_CZ}: ${SGML_CZ}
	sgml2txt --filter $<
${INFO_CZ}: ${SGML_CZ}
	sgml2info $<

${HTML_ZH}: ${SGML_ZH}
	sgml2html $<
${TXT_ZH}: ${SGML_ZH}
	sgml2txt --filter --charset=latin $<
${INFO_ZH}: ${SGML_ZH}
	sgml2info $<




install: all
	-@mkdir -p ${DOC_DIR} $(HTML_DIR)
	-@cp $(OTHER_DOCFILES) $(DOC_DIR)
	-@cp *.ps *.txt *.info $(DOC_DIR)
	-@cp *.html  ${HTML_DIR}


.PHONY: clean uninstall
uninstall:
	-@rm -fr ${DOC_DIR}
clean:
	-@rm -f *.bak *~ core *.ps *.html *.info *.txt
