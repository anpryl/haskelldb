TOP_DIR = .

SUBDIRS = src doc

include $(TOP_DIR)/rules.mk

DIST_DIR = haskelldb-$(PACKAGE_VERSION)

INSTALL_COMPILERS = $(addprefix install-,$(COMPILERS))

.PHONY: install $(INSTALL_COMPILERS) dist distclean maintainer-clean

all: src

configure: configure.ac aclocal.m4
	autoconf

config.status: configure
	./config.status --recheck

config.mk: config.mk.in config.status
	./config.status

haskelldb.pkg: haskelldb.pkg.in config.status
	./config.status

install: $(INSTALL_COMPILERS)

install-ghc:

install-hugs:

dist:
	mkdir $(DIST_DIR)
	cvs export -d $(DIST_DIR) -rHEAD hwt_haskelldb
	cd $(DIST_DIR) && autoconf && rm -rf autom4te.cache
	find $(DIST_DIR) -name .cvsignore -exec rm -f {} ';'
	tar -zcf $(DIST_DIR).tar.gz $(DIST_DIR)
	zip -r $(DIST_DIR).zip $(DIST_DIR)
	rm -rf $(DIST_DIR)

distclean: clean
	-rm -f config.status config.mk config.log 
	-rm -rf autom4te.cache

maintainer-clean: distclean
	-rm -f *.tar.gz *.zip