install:
	cp gloss.sh $(PREFIX)/usr/bin

uninstall:
	rm $(PREFIX)/usr/bin/gloss.sh

MANIFEST:
	echo /usr/bin/gloss.sh > MANIFEST
