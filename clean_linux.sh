#!/bin/sh
# clean_linux.sh — Limpieza modular Debian/Ubuntu (interactivo + flags)
# Requiere: root, utilidades GNU (find, head, sort, xargs -r)

set -eu

VERSION='2.0.0'

# --- Configuración (env) ---
JOURNAL_DAYS="${JOURNAL_DAYS:-7}"
KEEP_KERNELS="${KEEP_KERNELS:-2}"

# --- Flags globales ---
DRY_RUN=0
ASSUME_YES=0
ONLY_SAFE=0
AGGRESSIVE=0
WITH_LEGACY=0
SKIP_EMPTY_AUTOREMOVE=0
LIST_SECTIONS=0
LOG_FILE=''
MENU_MODE=''          # safe | full | aggressive
INTERACTIVE=0
AUTO_ACCEPT_RISK='' # low | medium | high
AGGRESSIVE_OK=0
FILTER_SECTIONS=''

# --- Utilidades ---

log_msg() {
	if [ -n "$LOG_FILE" ]; then
		printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
	fi
}

is_tty() {
	[ -t 1 ] && [ -t 0 ]
}

use_color() {
	[ -z "${NO_COLOR:-}" ] && is_tty
}

c_reset() { printf '\033[0m'; }
c_green() { if use_color; then printf '\033[0;32m'; fi; }
c_yellow() { if use_color; then printf '\033[1;33m'; fi; }
c_red() { if use_color; then printf '\033[1;31m'; fi; }

risk_label_es() {
	case "$1" in
	none) printf 'Informativo' ;;
	low) printf 'BAJO' ;;
	medium) printf 'MEDIO' ;;
	high) printf 'ALTO' ;;
	*) printf '%s' "$1" ;;
	esac
}

print_risk_line() {
	_risk=$1
	_label=$(risk_label_es "$_risk")
	case "$_risk" in
	high)
		c_red
		printf '  Riesgo: %s' "$_label"
		c_reset
		printf '\n'
		;;
	medium)
		c_yellow
		printf '  Riesgo: %s' "$_label"
		c_reset
		printf '\n'
		;;
	low)
		c_green
		printf '  Riesgo: %s' "$_label"
		c_reset
		printf '\n'
		;;
	*)
		printf '  Riesgo: %s\n' "$_label"
		;;
	esac
}

run_cmd() {
	log_msg "CMD: $*"
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  [DRY-RUN] %s\n' "$*"
		return 0
	fi
	"$@"
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		printf 'Error: ejecuta como root: sudo %s\n' "$0" >&2
		exit 1
	fi
}

check_apt_lock() {
	if [ -f /var/lib/dpkg/lock-frontend ] || [ -f /var/lib/dpkg/lock ]; then
		if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ||
			fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
			printf 'Error: APT/dpkg está en uso (lock activo). Espera y reintenta.\n' >&2
			exit 1
		fi
	fi
}

invoke_user() {
	if [ -n "${SUDO_USER:-}" ]; then
		printf '%s' "$SUDO_USER"
	else
		printf '%s' "${USER:-root}"
	fi
}

section_in_filter() {
	_id=$1
	if [ -z "$FILTER_SECTIONS" ]; then
		return 0
	fi
	# shellcheck disable=SC2086
	for _s in $FILTER_SECTIONS; do
		if [ "$_s" = "$_id" ]; then
			return 0
		fi
	done
	return 1
}

section_enabled_by_menu() {
	_id=$1
	_risk=$2

	if ! section_in_filter "$_id"; then
		return 1
	fi

	if [ "$ONLY_SAFE" -eq 1 ]; then
		case "$_risk" in
		none | low) return 0 ;;
		*) return 1 ;;
		esac
	fi

	case "$MENU_MODE" in
	safe)
		case "$_risk" in
		none | low) return 0 ;;
		*) return 1 ;;
		esac
		;;
	aggressive)
		case "$_id" in
		trash | man_pages | logs_truncate | kernels) return 0 ;;
		esac
		case "$_risk" in
		none | low) return 0 ;;
		medium)
			case "$_id" in
			trash | man_pages) return 0 ;;
			esac
			return 1
			;;
		high) return 0 ;;
		*) return 1 ;;
		esac
		;;
	full | '')
		if [ "$_id" = 'legacy_purge' ] && [ "$WITH_LEGACY" -eq 0 ]; then
			return 1
		fi
		return 0
		;;
	esac
	return 0
}

should_auto_accept() {
	_id=$1
	_risk=$2
	if [ "$ASSUME_YES" -eq 1 ]; then
		return 0
	fi
	if [ -n "$AUTO_ACCEPT_RISK" ]; then
		case "$_risk" in
		low) [ "$AUTO_ACCEPT_RISK" = 'low' ] && return 0 ;;
		medium)
			[ "$AUTO_ACCEPT_RISK" = 'low' ] || [ "$AUTO_ACCEPT_RISK" = 'medium' ] &&
				return 0
			;;
		high)
			[ "$AUTO_ACCEPT_RISK" = 'low' ] ||
				[ "$AUTO_ACCEPT_RISK" = 'medium' ] ||
				[ "$AUTO_ACCEPT_RISK" = 'high' ] && return 0
			;;
		esac
	fi
	if [ "$AGGRESSIVE_OK" -eq 1 ]; then
		case "$_risk" in
		low) return 0 ;;
		medium)
			case "$_id" in
			trash | man_pages) return 0 ;;
			esac
			;;
		high) return 1 ;;
		esac
	fi
	return 1
}

confirm_section() {
	_id=$1
	_risk=$2
	_desc=$3
	_cmds=$4
	_extra=${5:-}

	if [ "$_risk" = 'none' ]; then
		printf '\n── %s ──\n' "$_id"
		print_risk_line "$_risk"
		printf '  %s\n' "$_desc"
		# shellcheck disable=SC2086
		printf '  %s\n' $_cmds
		return 0
	fi

	if should_auto_accept "$_id" "$_risk"; then
		return 0
	fi

	if ! is_tty || [ "$INTERACTIVE" -eq 0 ]; then
		if [ "$ASSUME_YES" -eq 0 ]; then
			printf 'Omitido: %s (sin TTY interactivo; usa -y)\n' "$_id"
			return 1
		fi
		return 0
	fi

	printf '\n── %s ──────────────────────────\n' "$_id"
	print_risk_line "$_risk"
	printf '  %s\n' "$_desc"
	if [ -n "$_extra" ]; then
		printf '  %s\n' "$_extra"
	fi
	# shellcheck disable=SC2086
	printf '  Comando(s): %s\n' $_cmds

	printf '  ¿Ejecutar? [s]í / [n]o / [a] resto riesgo %s / [q]uit: ' "$(risk_label_es "$_risk")"
	read -r _ans || _ans='n'
	case "$_ans" in
	s | S | y | Y | sí | si)
		if [ "$_risk" = 'high' ] && [ "$AGGRESSIVE_OK" -eq 1 ]; then
			printf '\n  *** Confirmación adicional (riesgo ALTO): %s ***\n' "$_id"
			printf '  ¿Seguro que quieres ejecutar? [s/n]: '
			read -r _ans2 || _ans2='n'
			case "$_ans2" in
			s | S | y | Y | sí | si) return 0 ;;
			*)
				printf 'Omitido: %s (rechazado en 2.ª confirmación)\n' "$_id"
				return 1
				;;
			esac
		fi
		return 0
		;;
	a | A)
		AUTO_ACCEPT_RISK=$_risk
		return 0
		;;
	q | Q)
		printf 'Cancelado por el usuario.\n'
		exit 0
		;;
	*)
		printf 'Omitido: %s (riesgo %s)\n' "$_id" "$(risk_label_es "$_risk")"
		return 1
		;;
	esac
}

run_section() {
	_id=$1
	_risk=$2
	_desc=$3
	_cmds=$4
	_extra=${5:-}

	if ! section_enabled_by_menu "$_id" "$_risk"; then
		return 0
	fi

	if ! confirm_section "$_id" "$_risk" "$_desc" "$_cmds" "$_extra"; then
		return 0
	fi

	log_msg "RUN section: $_id"
	"do_${_id}" || {
		printf 'Error en sección %s\n' "$_id" >&2
		return 1
	}
}

# --- Secciones informativas ---

do_disk_info() {
	printf '\n=== Espacio en disco ===\n'
	df -h / /home 2>/dev/null || df -h /
}

do_apt_show_cache() {
	if [ -d /var/cache/apt/archives ]; then
		printf '\n=== Caché APT ===\n'
		du -sh /var/cache/apt/archives 2>/dev/null || true
	fi
}

# --- Secciones de limpieza ---

do_apt_cache() {
	run_cmd apt-get clean
	run_cmd apt-get autoclean
}

apt_autoremove_preview() {
	_preview_out=$(mktemp)
	apt-get -s autoremove >"$_preview_out" 2>&1 || true
	printf '\n  --- Vista previa (apt-get -s autoremove) ---\n'
	if [ -s "$_preview_out" ] &&
		grep -qiE 'will be REMOVED|REMOVERÁN|serán eliminados|to remove' "$_preview_out" 2>/dev/null; then
		sed 's/^/  /' <"$_preview_out"
		rm -f "$_preview_out"
		return 0
	fi
	printf '  (ningún paquete para eliminar)\n'
	rm -f "$_preview_out"
	return 1
}

do_apt_autoremove() {
	if ! apt_autoremove_preview; then
		if [ "$SKIP_EMPTY_AUTOREMOVE" -eq 1 ]; then
			return 0
		fi
		if [ "$INTERACTIVE" -eq 1 ] && is_tty && [ "$ASSUME_YES" -eq 0 ]; then
			return 0
		fi
		if [ "$DRY_RUN" -eq 1 ]; then
			printf '  [DRY-RUN] apt-get autoremove -y (no aplicable; simulación vacía)\n'
		fi
		return 0
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  [DRY-RUN] apt-get autoremove -y\n'
		return 0
	fi

	if [ "$INTERACTIVE" -eq 1 ] && is_tty && [ "$ASSUME_YES" -eq 0 ]; then
		printf '  ¿Continuar con autoremove real? [s/n]: '
		read -r _go || _go='n'
		case "$_go" in
		s | S | y | Y | sí | si) ;;
		*)
			printf 'Omitido: autoremove real\n'
			return 0
			;;
		esac
	fi

	run_cmd apt-get autoremove -y
}

do_logs_rotated() {
	find /var/log -type f \( -name '*.gz' -o -regex '.*/.*\.[0-9]+$' \) -print0 2>/dev/null |
		while IFS= read -r -d '' _f; do
			run_cmd rm -f "$_f"
		done
}

do_journal_vacuum() {
	if command -v journalctl >/dev/null 2>&1; then
		run_cmd journalctl --vacuum-time="${JOURNAL_DAYS}d"
	else
		printf '  journalctl no disponible; se omite.\n'
	fi
}

do_trash() {
	for _home in /home/* /root; do
		_trash="$_home/.local/share/Trash"
		if [ -d "$_trash" ]; then
			find "$_trash" -mindepth 1 -maxdepth 1 -print0 2>/dev/null |
				while IFS= read -r -d '' _item; do
					run_cmd rm -rf "$_item"
				done
		fi
	done
}

do_user_cache() {
	_u=$(invoke_user)
	_home=$(getent passwd "$_u" 2>/dev/null | cut -d: -f6)
	if [ -z "$_home" ] || [ ! -d "$_home/.cache" ]; then
		printf '  No se encontró ~/.cache para %s\n' "$_u"
		return 0
	fi
	if [ "$DRY_RUN" -eq 0 ]; then
		du -sh "$_home/.cache" 2>/dev/null || true
	fi
	find "$_home/.cache" -mindepth 1 -maxdepth 1 -print0 2>/dev/null |
		while IFS= read -r -d '' _item; do
			run_cmd rm -rf "$_item"
		done
}

do_snap_revisions() {
	if ! command -v snap >/dev/null 2>&1; then
		printf '  snap no instalado; se omite.\n'
		return 0
	fi
	snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' |
		while read -r _name _rev; do
			[ -n "$_name" ] || continue
			run_cmd snap remove "$_name" --revision="$_rev"
		done
}

do_flatpak_unused() {
	if ! command -v flatpak >/dev/null 2>&1; then
		printf '  flatpak no instalado; se omite.\n'
		return 0
	fi
	if flatpak uninstall --unused --dry-run >/dev/null 2>&1; then
		printf '  --- Vista previa flatpak ---\n'
		flatpak uninstall --unused --dry-run 2>&1 | sed 's/^/  /' || true
		if [ "$DRY_RUN" -eq 1 ]; then
			return 0
		fi
	else
		printf '  (flatpak sin --dry-run; se listará al ejecutar)\n'
		if [ "$DRY_RUN" -eq 1 ]; then
			printf '  [DRY-RUN] flatpak uninstall --unused -y\n'
			return 0
		fi
	fi
	run_cmd flatpak uninstall --unused -y
}

do_deborphan() {
	if ! command -v deborphan >/dev/null 2>&1; then
		printf '  deborphan no instalado; se omite.\n'
		return 0
	fi
	_pkgs=$(deborphan 2>/dev/null || true)
	if [ -z "$_pkgs" ]; then
		printf '  No hay paquetes huérfanos reportados.\n'
		return 0
	fi
	printf '  Paquetes: %s\n' "$_pkgs"
	# shellcheck disable=SC2086
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  [DRY-RUN] apt-get remove --purge -y %s\n' "$_pkgs"
		return 0
	fi
	# shellcheck disable=SC2086
	run_cmd apt-get remove --purge -y $_pkgs
}

do_man_pages() {
	run_cmd rm -rf /usr/share/man/?? /usr/share/man/??_*
}

do_logs_truncate() {
	find /var/log -type f -print0 2>/dev/null |
		while IFS= read -r -d '' _f; do
			if [ "$DRY_RUN" -eq 1 ]; then
				printf '  [DRY-RUN] truncate > %s\n' "$_f"
			else
				: >"$_f"
				log_msg "truncate $_f"
			fi
		done
}

kernel_version_key() {
	# Extrae clave de versión desde nombre de paquete linux-image-X.Y.Z-...
	echo "$1" | sed -n 's/^linux-image-\([0-9][0-9.a-zA-Z~-]*\).*/\1/p'
}

do_kernels() {
	if ! command -v dpkg >/dev/null 2>&1; then
		printf '  dpkg no disponible.\n'
		return 1
	fi

	_running=$(uname -r)

	printf '  Kernel en uso: %s\n' "$_running"

	_images=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' | grep -E '^linux-image-[0-9]' || true)
	if [ -z "$_images" ]; then
		printf '  No hay paquetes linux-image adicionales.\n'
		return 0
	fi

	_keep_list=$(mktemp)
	_purge_list=$(mktemp)
	trap 'rm -f "$_keep_list" "$_purge_list"' EXIT INT HUP

	# Versiones únicas ordenadas (más reciente al final con sort -V)
	for _pkg in $_images; do
		kernel_version_key "$_pkg"
	done | sort -u -V >"$_keep_list"

	_total=$(wc -l <"$_keep_list" | tr -d ' ')
	_keep_n=$KEEP_KERNELS
	if [ "$_total" -le "$_keep_n" ]; then
		printf '  Se mantienen %s versiones (<= KEEP_KERNELS=%s); nada que purgar.\n' "$_total" "$KEEP_KERNELS"
		rm -f "$_keep_list" "$_purge_list"
		trap - EXIT INT HUP
		return 0
	fi

	# Mantener las últimas KEEP_KERNELS versiones
	_to_keep=$(tail -n "$_keep_n" "$_keep_list")

	_running_pkg="linux-image-${_running}"

	for _pkg in $_images; do
		_ver=$(kernel_version_key "$_pkg")
		_keep_this=0
		if [ "$_pkg" = "$_running_pkg" ]; then
			_keep_this=1
		fi
		for _k in $_to_keep; do
			if [ "$_ver" = "$_k" ]; then
				_keep_this=1
				break
			fi
		done

		if [ "$_keep_this" -eq 0 ]; then
			echo "$_pkg" >>"$_purge_list"
			_hdr=$(echo "$_pkg" | sed 's/linux-image-/linux-headers-/')
			dpkg -l "$_hdr" 2>/dev/null | awk '/^ii/ {print $2}' >>"$_purge_list" || true
		fi
	done

	if [ ! -s "$_purge_list" ]; then
		printf '  Ningún kernel candidato a purga.\n'
		rm -f "$_keep_list" "$_purge_list"
		trap - EXIT INT HUP
		return 0
	fi

	printf '  Paquetes a purgar:\n'
	sed 's/^/    /' <"$_purge_list"

	# Headers del kernel activo si faltan
	_active_hdr=$(echo "$_running" | sed -n 's/^\([0-9]*\.[0-9]*\.[0-9]*\)-\([^-]*\)-\(.*\)$/\1-\2/p')
	if [ -n "$_active_hdr" ]; then
		_hdr_pkg="linux-headers-${_active_hdr}"
		if ! dpkg -l "$_hdr_pkg" 2>/dev/null | awk '/^ii/ {found=1} END{exit !found}'; then
			printf '  Sugerencia: podrías instalar %s si compilas módulos.\n' "$_hdr_pkg"
		fi
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  [DRY-RUN] apt-get purge -y <lista anterior>\n'
		rm -f "$_keep_list" "$_purge_list"
		trap - EXIT INT HUP
		return 0
	fi

	_purge_pkgs=$(tr '\n' ' ' <"$_purge_list")
	rm -f "$_keep_list" "$_purge_list"
	trap - EXIT INT HUP

	# shellcheck disable=SC2086
	run_cmd apt-get purge -y $_purge_pkgs
}

do_legacy_purge() {
	run_cmd apt-get remove --purge -y software-properties-common
}

# --- Orquestación ---

show_initial_menu() {
	if ! is_tty || [ "$INTERACTIVE" -eq 0 ]; then
		MENU_MODE=full
		return
	fi
	printf '\n=== clean-linux %s ===\n' "$VERSION"
	printf '  [1] Solo seguro (riesgo BAJO)\n'
	printf '  [2] Sección a sección (todas, con confirmación)\n'
	printf '  [3] Perfil agresivo (papelera, man, logs, kernels)\n'
	printf '  [4] Salir\n'
	printf 'Opción [1-4]: '
	read -r _opt || _opt='4'
	case "$_opt" in
	1) MENU_MODE=safe ;;
	2) MENU_MODE=full ;;
	3) MENU_MODE=aggressive ;;
	*) printf 'Saliendo.\n'; exit 0 ;;
	esac
}

confirm_aggressive_global() {
	if [ "$AGGRESSIVE" -eq 0 ] && [ "$MENU_MODE" != 'aggressive' ]; then
		return 0
	fi
	printf '\nPerfil agresivo incluye:\n'
	printf '  [MEDIO] trash, man_pages\n'
	printf '  [ALTO]  logs_truncate, kernels\n'
	printf '(No incluye user_cache ni flatpak por defecto)\n'
	if [ "$ASSUME_YES" -eq 1 ]; then
		AGGRESSIVE_OK=1
		return 0
	fi
	if ! is_tty; then
		AGGRESSIVE_OK=1
		return 0
	fi
	printf '¿Ejecutar el bloque agresivo? [s/n]: '
	read -r _g || _g='n'
	case "$_g" in
	s | S | y | Y | sí | si) AGGRESSIVE_OK=1 ;;
	*) MENU_MODE=safe ;;
	esac
}

list_all_sections() {
	printf 'Secciones disponibles:\n'
	printf '  %-22s %s\n' 'disk_info' 'Informativo'
	printf '  %-22s %s\n' 'apt_show_cache' 'Informativo'
	printf '  %-22s %s\n' 'apt_cache' 'BAJO'
	printf '  %-22s %s\n' 'apt_autoremove' 'BAJO (vista previa -s)'
	printf '  %-22s %s\n' 'logs_rotated' 'BAJO'
	printf '  %-22s %s\n' 'journal_vacuum' 'BAJO'
	printf '  %-22s %s\n' 'trash' 'MEDIO'
	printf '  %-22s %s\n' 'user_cache' 'MEDIO'
	printf '  %-22s %s\n' 'snap_revisions' 'MEDIO'
	printf '  %-22s %s\n' 'flatpak_unused' 'MEDIO'
	printf '  %-22s %s\n' 'deborphan' 'MEDIO'
	printf '  %-22s %s\n' 'man_pages' 'MEDIO'
	printf '  %-22s %s\n' 'logs_truncate' 'ALTO'
	printf '  %-22s %s\n' 'kernels' 'ALTO'
	printf '  %-22s %s\n' 'legacy_purge' 'MEDIO (--with-legacy)'
}

run_all_sections() {
	do_disk_info
	run_section apt_show_cache none \
		'Tamaño de la caché de paquetes APT.' \
		'du -sh /var/cache/apt/archives'

	run_section apt_cache low \
		'Limpia paquetes .deb descargados y caché obsoleta de APT.' \
		'apt-get clean && apt-get autoclean'

	run_section apt_autoremove low \
		'Elimina dependencias que ya no necesita ningún paquete instalado.' \
		'apt-get -s autoremove (vista previa) && apt-get autoremove -y'

	run_section logs_rotated low \
		'Borra logs comprimidos (.gz) y rotados numéricos en /var/log.' \
		'find /var/log -name *.gz / *.[0-9] -delete'

	run_section journal_vacuum low \
		"Reduce el journal de systemd a ${JOURNAL_DAYS} días." \
		"journalctl --vacuum-time=${JOURNAL_DAYS}d"

	run_section trash medium \
		'Vacia la papelera de TODOS los usuarios en /home y de root.' \
		'rm -rf .../Trash/*' \
		'ADVERTENCIA: archivos eliminados de la papelera no se recuperan fácilmente.'

	run_section user_cache medium \
		'Borra el contenido de ~/.cache del usuario que invocó sudo.' \
		'rm -rf ~/.cache/*' \
		'Puede cerrar sesiones o forzar re-descargas en aplicaciones.'

	run_section snap_revisions medium \
		'Elimina revisiones snap deshabilitadas (ahorra espacio).' \
		'snap remove <app> --revision=<rev>'

	run_section flatpak_unused medium \
		'Desinstala runtimes y apps Flatpak sin referencias.' \
		'flatpak uninstall --unused -y'

	run_section deborphan medium \
		'Elimina paquetes huérfanos listados por deborphan.' \
		'apt-get remove --purge -y <paquetes>'

	run_section man_pages medium \
		'Elimina páginas de manual en /usr/share/man (comando man dejará de tener docs locales).' \
		'rm -rf /usr/share/man/??*'

	run_section logs_truncate high \
		'Vacía (trunca) TODOS los ficheros de registro en /var/log.' \
		': > cada fichero en /var/log' \
		'ADVERTENCIA: pierdes historial de logs; puede dificultar auditoría y depuración.'

	run_section kernels high \
		"Purga kernels antiguos; conserva ${KEEP_KERNELS} versiones recientes y el kernel en uso." \
		'apt-get purge -y linux-image-...' \
		'ADVERTENCIA: un error puede impedir arrancar; revisa la lista antes de aceptar.'

	if [ "$WITH_LEGACY" -eq 1 ]; then
		run_section legacy_purge medium \
			'Elimina software-properties-common (add-apt-repository / PPAs).' \
			'apt-get remove --purge -y software-properties-common' \
			'ADVERTENCIA: puede romper gestión de repositorios adicionales.'
	fi
}

usage() {
	cat <<EOF
clean-linux $VERSION — Limpieza Debian/Ubuntu

Uso: sudo $0 [opciones]

Opciones:
  -h, --help                 Esta ayuda
  -n, --dry-run              Simular (no modificar; apt -s autoremove sí se ejecuta)
  -y, --yes                  No preguntar (aceptar secciones activas)
  --only-safe                Solo secciones de riesgo BAJO
  --aggressive               Perfil agresivo (+ confirmación en ALTO)
  --section=ID               Limitar a sección(es); repetible (pregunta si hay TTY)
  --with-legacy              Incluye legacy_purge (software-properties-common)
  --list-sections            Lista IDs y niveles de riesgo
  --log-file=RUTA            Registro de acciones
  --skip-empty-autoremove    No ejecutar autoremove si la simulación está vacía

Variables de entorno:
  JOURNAL_DAYS=7             Retención journalctl
  KEEP_KERNELS=2             Versiones de kernel a conservar
  NO_COLOR=1                 Sin colores ANSI

Ejemplos:
  sudo $0                      Interactivo con menú
  sudo $0 --only-safe -y       Cron / limpieza segura
  sudo $0 -n --aggressive      Ver plan agresivo sin ejecutar
  sudo $0 --section=kernels -y Solo kernels (¡cuidado!)

EOF
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		-n | --dry-run)
			DRY_RUN=1
			;;
		-y | --yes)
			ASSUME_YES=1
			;;
		--only-safe)
			ONLY_SAFE=1
			;;
		--aggressive)
			AGGRESSIVE=1
			MENU_MODE=aggressive
			;;
		--with-legacy)
			WITH_LEGACY=1
			;;
		--list-sections)
			LIST_SECTIONS=1
			;;
		--skip-empty-autoremove)
			SKIP_EMPTY_AUTOREMOVE=1
			;;
		--log-file=*)
			LOG_FILE=${1#*=}
			;;
		--log-file)
			shift
			LOG_FILE=${1:-}
			;;
		--section=*)
			_sid=${1#*=}
			FILTER_SECTIONS="$FILTER_SECTIONS $_sid"
			;;
		--section)
			shift
			FILTER_SECTIONS="$FILTER_SECTIONS ${1:-}"
			;;
		*)
			printf 'Opción desconocida: %s\n' "$1" >&2
			usage >&2
			exit 1
			;;
		esac
		shift
	done
}

main() {
	parse_args "$@"

	if [ "$LIST_SECTIONS" -eq 1 ]; then
		list_all_sections
		exit 0
	fi

	require_root
	check_apt_lock

	if [ -n "$FILTER_SECTIONS" ] && ! is_tty; then
		ASSUME_YES=1
	fi

	if is_tty && [ "$ASSUME_YES" -eq 0 ]; then
		INTERACTIVE=1
	fi

	if [ "$AGGRESSIVE" -eq 1 ]; then
		MENU_MODE=aggressive
	elif [ "$ONLY_SAFE" -eq 1 ]; then
		MENU_MODE=safe
	fi

	if [ "$INTERACTIVE" -eq 1 ] && [ -z "$FILTER_SECTIONS" ] &&
		[ "$ONLY_SAFE" -eq 0 ] && [ "$AGGRESSIVE" -eq 0 ] && [ -z "$MENU_MODE" ]; then
		show_initial_menu
	fi

	if [ -z "$MENU_MODE" ]; then
		MENU_MODE=full
	fi

	confirm_aggressive_global

	if [ -n "$LOG_FILE" ]; then
		: >"$LOG_FILE"
		log_msg "Inicio clean-linux $VERSION"
	fi

	run_all_sections

	printf '\n=== Resumen final ===\n'
	do_disk_info
	do_apt_show_cache
	printf '\nLimpieza finalizada.\n'
	log_msg 'Fin'
}

main "$@"
