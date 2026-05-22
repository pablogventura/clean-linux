#!/bin/sh
# Instala clean_linux.sh en /usr/local/bin/clean-linux
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SOURCE="${SCRIPT_DIR}/clean_linux.sh"
TARGET_BIN="/usr/local/bin/clean-linux"
DOC_DIR="/usr/local/share/doc/clean-linux"

install_bins() {
	if [ ! -f "$SOURCE" ]; then
		printf 'Error: no se encuentra %s\n' "$SOURCE" >&2
		exit 1
	fi
	install -d /usr/local/bin
	install -m 755 "$SOURCE" "$TARGET_BIN"
	printf 'Instalado: %s\n' "$TARGET_BIN"
	if [ -f "${SCRIPT_DIR}/README.md" ]; then
		install -d "$DOC_DIR"
		install -m 644 "${SCRIPT_DIR}/README.md" "${DOC_DIR}/README.md"
		printf 'Documentación: %s/README.md\n' "$DOC_DIR"
	fi
}

uninstall_bins() {
	if [ -f "$TARGET_BIN" ]; then
		rm -f "$TARGET_BIN"
		printf 'Eliminado: %s\n' "$TARGET_BIN"
	else
		printf 'No estaba instalado: %s\n' "$TARGET_BIN"
	fi
	if [ -d "$DOC_DIR" ]; then
		rm -rf "$DOC_DIR"
		printf 'Eliminado: %s\n' "$DOC_DIR"
	fi
}

case "${1:-install}" in
install)
	if [ "$(id -u)" -ne 0 ]; then
		printf 'Ejecuta: sudo %s install\n' "$0" >&2
		exit 1
	fi
	install_bins
	;;
uninstall)
	if [ "$(id -u)" -ne 0 ]; then
		printf 'Ejecuta: sudo %s uninstall\n' "$0" >&2
		exit 1
	fi
	uninstall_bins
	;;
*)
	printf 'Uso: sudo %s [install|uninstall]\n' "$0" >&2
	exit 1
	;;
esac
