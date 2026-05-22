# clean-linux

Script de limpieza para **Debian/Ubuntu** con confirmación interactiva, niveles de riesgo visibles y modo automatizable para cron.

## Requisitos

- Ejecución como **root** (`sudo`)
- Utilidades **GNU** (`find`, `head`, `sort`, `xargs -r`, `fuser`)
- Opcionales: `snap`, `flatpak`, `deborphan`, `journalctl`

Al inicio y al final muestra **espacio usado y libre** en la partición `/` (o `DISK_MOUNT`), y la **ganancia** en tamaño y porcentaje.

## Uso rápido

```bash
chmod +x clean_linux.sh
sudo ./clean_linux.sh              # Menú interactivo
sudo ./clean_linux.sh --only-safe -y   # Limpieza segura (cron)
sudo ./clean_linux.sh -n           # Simulación (dry-run)
sudo ./clean_linux.sh --list-sections
```

## Menú interactivo

1. **Solo seguro** — APT, logs rotados, journal (riesgo BAJO). **No vacía la papelera.**
2. **Sección a sección** — Todas las tareas con confirmación y etiqueta de riesgo
3. **Perfil agresivo** — Papelera, man pages, truncar logs, kernels (con confirmación global + extra en ALTO)
4. **Salir**

Solo papelera: `sudo ./clean_linux.sh --section=trash`

Cada sección muestra `Riesgo: BAJO|MEDIO|ALTO`, descripción, comandos y opciones `[s/n/a/q]`. En perfil agresivo, las secciones **ALTO** piden confirmación dos veces.

## Opciones

| Opción | Descripción |
|--------|-------------|
| `-n`, `--dry-run` | No modifica el sistema; ejecuta `apt-get -s autoremove` para mostrar vista previa |
| `-y`, `--yes` | Sin preguntas |
| `--only-safe` | Solo secciones de riesgo bajo |
| `--aggressive` | Bloque agresivo (ver README) |
| `--section=ID` | Solo esa sección (repetible; pregunta si hay terminal) |
| `--with-legacy` | Incluye `legacy_purge` (software-properties-common) |
| `--list-sections` | Lista IDs y riesgos |
| `--log-file=RUTA` | Registro con marcas de tiempo |
| `--skip-empty-autoremove` | No ejecutar autoremove si la simulación no propone paquetes |

## Variables de entorno

| Variable | Default | Uso |
|----------|---------|-----|
| `JOURNAL_DAYS` | `7` | `journalctl --vacuum-time` |
| `KEEP_KERNELS` | `2` | Versiones de kernel a conservar |
| `DISK_MOUNT` | `/` | Punto de montaje para el informe antes/después |
| `NO_COLOR` | — | Desactiva colores en TTY |

## Secciones

| ID | Riesgo |
|----|--------|
| `apt_cache`, `apt_autoremove`, `logs_rotated`, `journal_vacuum` | Bajo |
| `trash`, `user_cache`, `snap_revisions`, `flatpak_unused`, `deborphan`, `man_pages` | Medio |
| `logs_truncate`, `kernels` | Alto |
| `legacy_purge` | Medio (solo `--with-legacy`) |

`apt_autoremove` muestra primero la salida de `apt-get -s autoremove` y luego pregunta si continuar (en modo interactivo).

## Instalación global

```bash
sudo ./install.sh install
# o
sudo make install

clean-linux --help
sudo ./install.sh uninstall   # o: sudo make uninstall
```

Instala en `/usr/local/bin/clean-linux`.

## Advertencias

- **`kernels`**: revisa la lista antes de purgar; un error puede afectar el arranque.
- **`logs_truncate`**: pierdes historial de logs en `/var/log`.
- **`trash`**: vacía la papelera de **todos** los usuarios en `/home` y de root.
- **`man_pages`**: elimina documentación local de `man`.
- **`legacy_purge`**: quita `software-properties-common` (PPAs / `add-apt-repository`).

## Checklist de pruebas

```bash
./clean_linux.sh --help
./clean_linux.sh --list-sections
./clean_linux.sh          # debe pedir root
sudo ./clean_linux.sh -n
sudo ./clean_linux.sh --only-safe -y
sudo ./clean_linux.sh --aggressive -n
sudo ./clean_linux.sh --section=kernels -n
```

## Licencia

Uso libre; sin garantía. Revisa en máquina de prueba antes de producción.
