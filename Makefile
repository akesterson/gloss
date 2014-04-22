VERSION:=$(shell if [ -d .git ]; then bash -c 'gitversion.sh | grep "^MAJOR=" | cut -d = -f 2'; else source version.sh && echo $$MAJOR ; fi)
RELEASE:=$(shell if [ -d .git ]; then bash -c 'gitversion.sh | grep "^BUILD=" | cut -d = -f 2'; else source version.sh && echo $$BUILD ; fi)
DISTFILE=./dist/gloss-$(VERSION)-$(RELEASE).tar.gz
SPECFILE=gloss.spec
ifndef RHEL_VERSION
	RHEL_VERSION=5
endif
ifeq ($(RHEL_VERSION),5)
        MOCKFLAGS=--define "_source_filedigest_algorithm md5" --define "_binary_filedigest_algorithm md5"
endif

ifndef PREFIX
	PREFIX=''
endif

RHEL_RELEASE:=$(RELEASE).el$(RHEL_VERSION)
SRPM=gloss-$(VERSION)-$(RHEL_RELEASE).src.rpm
RPM=gloss-$(VERSION)-$(RHEL_RELEASE).noarch.rpm
RHEL_DISTFILE=./dist/gloss-$(VERSION)-$(RHEL_RELEASE).tar.gz
DISTFILE_DEPS=$(shell find . -type f | grep -Ev '\.git|\./dist/|$(DISTFILE)')

all: ./dist/$(RPM)

# --- PHONY targets

.PHONY: clean srpm rpm gitclean dist
clean:
	rm -f $(DISTFILE)
	rm -fr dist/gloss-$(VERSION)-$(RELEASE)*

dist: $(DISTFILE)

srpm: ./dist/$(SRPM)

rpm: ./dist/$(RPM) ./dist/$(SRPM)

gitclean:
	git clean -df

# --- End phony targets

version.sh:
	gitversion.sh > version.sh

$(DISTFILE): version.sh
	mkdir -p dist/
	mkdir dist/gloss-$(VERSION)-$(RELEASE) || rm -fr dist/gloss-$(VERSION)-$(RELEASE)
	rsync -aWH . --exclude=.git --exclude=dist ./dist/gloss-$(VERSION)-$(RELEASE)/
	cd dist && tar -czvf ../$@ gloss-$(VERSION)-$(RELEASE)

$(RHEL_DISTFILE): $(DISTFILE)
	cd dist && \
		cp -R gloss-$(VERSION)-$(RELEASE) gloss-$(VERSION)-$(RHEL_RELEASE) && \
		tar -czvf ../$@ gloss-$(VERSION)-$(RHEL_RELEASE)

./dist/$(SRPM): $(RHEL_DISTFILE)
	rm -fr ./dist/$(SRPM)
	mock --verbose -r epel-$(RHEL_VERSION)-noarch --buildsrpm $(MOCKFLAGS) --spec $(SPECFILE) --sources ./dist/ --resultdir ./dist/ --define "version $(VERSION)" --define "release $(RHEL_RELEASE)"

./dist/$(RPM): ./dist/$(SRPM)
	rm -fr ./dist/$(RPM)
	mock --verbose -r epel-$(RHEL_VERSION)-noarch ./dist/$(SRPM) --resultdir ./dist/ --define "version $(VERSION)" --define "release $(RHEL_RELEASE)"

uninstall:
	rm -f $(PREFIX)/usr/bin/gloss.sh


install:
	mkdir -p $(PREFIX)/usr/bin
	install ./gloss.sh $(PREFIX)/usr/bin/gloss.sh

MANIFEST:
	echo /usr/bin/gloss.sh > MANIFEST
