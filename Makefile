PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/clean-linux

.PHONY: install uninstall

install:
	install -d $(BINDIR)
	install -m 755 clean_linux.sh $(BINDIR)/clean-linux
	install -d $(DOCDIR)
	install -m 644 README.md $(DOCDIR)/README.md
	@echo "Instalado: $(BINDIR)/clean-linux"

uninstall:
	rm -f $(BINDIR)/clean-linux
	rm -rf $(DOCDIR)
	@echo "Desinstalado clean-linux"
