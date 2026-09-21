*This project has been created as part of the 42 curriculum by <tu_login>.*

# 🛡️ Born2BeRoot — Guía Tutorial y Verificación de Requisitos (Debian)

¡Bienvenido/a a la guía paso a paso de **Born2BeRoot**! Este repositorio está diseñado para servir como **tutorial genérico, plantilla de entrega y guía de preparación para la defensa** de 42.

Contiene las instrucciones detalladas de configuración de un servidor seguro en **Debian**, la teoría necesaria para la evaluación, las pautas para generar la firma de entrega y un **script automatizado** para verificar que tu máquina cumple el 100% de los requisitos obligatorios del *subject*.

---

## 📌 Resumen de Requisitos Obligatorios

| Componente | Requisito del Subject | Estado / Configuración |
| :--- | :--- | :--- |
| **Sistema Operativo** | Debian (sin interfaz gráfica) | Instalación mínima (netinst) |
| **Hostname** | `<login>42` | Ejemplo: `gorkgall42` |
| **Particionado** | LVM sobre Cifrado LUKS | `/boot` fuera de LVM; `/`, `/home`, `/var`, `/var/log` y `swap` dentro |
| **SSH** | Puerto 4242 único / Sin root | `PermitRootLogin no`, puerto `4242` |
| **Firewall (UFW)** | Activo al arrancar | Solo el puerto `4242/tcp` permitido |
| **Sudo** | Política estricta + auditoría | `passwd_tries=3`, `secure_path`, logs en `/var/log/sudo/sudo.log` |
| **Contraseñas** | PAM `pwquality` + `login.defs` | Expiración 30 días, minlen=10, mayús/minús/dígito, maxrepeat=3 |
| **Monitoreo** | Script `monitoring.sh` + Cron | Ejecución cada 10 min y `@reboot` emitiendo mediante `wall` |
| **Seguridad MAC** | AppArmor activo | Habilitado por defecto en Debian |

---

## 🛠️ Guía Paso a Paso de Configuración

### 1. Instalación y Particionado LVM + Cifrado LUKS
1. Descarga la ISO **Debian Netinst** (x86_64).
2. Durante el asistente de instalación:
   * **Hostname:** Configura `<login>42` (ej. `student42`).
   * **Dominio:** Déjalo en blanco.
   * **Método de particionado:** Selecciona **Guiado - Utilizar todo el disco y configurar LVM cifrado**.
   * **Estructura de particiones obligatoria:**
     * `/boot`: Partición ext4 fuera de LVM/cifrado.
     * En el volumen cifrado `sda5_crypt` (LVM Group):
       * Volume `/` (root): ~10 GB
       * Volume `/home`: ~5 GB
       * Volume `/var`: ~3 GB
       * Volume `/var/log`: ~2 GB
       * Volume `swap`: ~1 GB (o acorde a la RAM)

### 2. Configuración de Usuarios y Sudo
1. Crea el grupo `user42` e incluye a tu usuario principal:
   ```bash
   sudo groupadd user42
   sudo usermod -aG user42 <tu_usuario>
   sudo usermod -aG sudo <tu_usuario>
   ```
2. Configura las reglas de `sudo`:
   Crea el directorio de auditoría y edita `/etc/sudoers` usando `sudo visudo`:
   ```bash
   sudo mkdir -p /var/log/sudo
   sudo visudo
   ```
   Añade las siguientes directivas debajo de `Defaults`:
   ```text
   Defaults    passwd_tries=3
   Defaults    badpass_message="Contraseña incorrecta. Inténtalo de nuevo."
   Defaults    logfile="/var/log/sudo/sudo.log"
   Defaults    log_input, log_output
   Defaults    requiretty
   Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
   ```

### 3. Política de Contraseñas (PAM y `login.defs`)
1. Edita `/etc/login.defs` para establecer la caducidad:
   ```text
   PASS_MAX_DAYS   30
   PASS_MIN_DAYS   2
   PASS_WARN_AGE   7
   ```
2. Instala la librería de calidad de contraseñas de PAM:
   ```bash
   sudo apt update && sudo apt install -y libpam-pwquality
   ```
3. Edita `/etc/pam.d/common-password` localizando la línea de `pam_pwquality.so` y añadiendo los parámetros requeridos:
   ```text
   password    requisite    pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 reject_username enforce_for_root
   ```

### 4. Servidor SSH y Cortafuegos UFW
1. Cambia el puerto en `/etc/ssh/sshd_config`:
   ```text
   Port 4242
   PermitRootLogin no
   ```
2. **Nota en Debian 12:** Si el puerto no cambia, desactiva el socket de systemd:
   ```bash
   sudo systemctl stop ssh.socket
   sudo systemctl disable ssh.socket
   sudo systemctl restart ssh.service
   ```
3. Configura UFW:
   ```bash
   sudo apt install -y ufw
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 4242/tcp
   sudo ufw enable
   ```

### 5. Script de Monitoreo (`monitoring.sh`) y Cron
1. Crea el script en `/usr/local/bin/monitoring.sh`:
   ```bash
   sudo nano /usr/local/bin/monitoring.sh
   sudo chmod +x /usr/local/bin/monitoring.sh
   ```
   *(Asegúrate de que obtenga la arquitectura, CPU física/vCPU, RAM, Disco, Carga CPU, Último reinicio, LVM activo, Conexiones TCP, Usuarios e IP/MAC).*
2. Programa la ejecución en el `crontab` de `root`:
   ```bash
   sudo crontab -e
   ```
   Añade las dos líneas al final:
   ```text
   */10 * * * * /usr/local/bin/monitoring.sh
   @reboot sleep 30 && /usr/local/bin/monitoring.sh
   ```

---

## 🔍 Script de Verificación Automática de Requisitos (`check_born2beroot.sh`)

Para comprobar en un solo comando si tu máquina cumple con todo el *subject* antes de la evaluación, guarda y ejecuta este script en tu Debian:

```bash
#!/bin/bash

# ==============================================================================
# Script de Comprobación de Requisitos - Born2BeRoot (42)
# Ejecutar en Debian con: sudo bash check_born2beroot.sh
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================"${NC}
echo -e "${BLUE}    VERIFICADOR DE REQUISITOS BORN2BEROOT (42)      "${NC}
echo -e "${BLUE}======================================================"${NC}
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Este script debe ejecutarse como root (sudo bash check_born2beroot.sh)${NC}"
  exit 1
fi

# 1. HOSTNAME
echo -e "${YELLOW}[1/8] Verificando Hostname...${NC}"
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" =~ 42$ ]]; then
  echo -e "  ${GREEN}[OK] Hostname es '$HOSTNAME' (termina en 42)${NC}"
else
  echo -e "  ${RED}[ERROR] Hostname es '$HOSTNAME' (NO termina en 42)${NC}"
fi
echo ""

# 2. CIFRADO LUKS Y LVM
echo -e "${YELLOW}[2/8] Verificando LVM y Cifrado LUKS...${NC}"
if blkid | grep -q "crypto_LUKS"; then
  echo -e "  ${GREEN}[OK] Partición cifrada LUKS detectada${NC}"
else
  echo -e "  ${RED}[ERROR] No se detectó ninguna partición cifrada LUKS (crypto_LUKS)${NC}"
fi

LVM_COUNT=$(lsblk | grep -c "lvm")
if [ "$LVM_COUNT" -ge 2 ]; then
  echo -e "  ${GREEN}[OK] Se detectaron volúmenes LVM ($LVM_COUNT LVs)${NC}"
else
  echo -e "  ${RED}[ERROR] Se encontraron menos de 2 volúmenes LVM ($LVM_COUNT encontrados)${NC}"
fi

BOOT_MOUNT=$(lsblk -o MOUNTPOINTS,TYPE | grep "/boot" | grep -v "lvm")
if [ -n "$BOOT_MOUNT" ]; then
  echo -e "  ${GREEN}[OK] /boot está montado fuera de LVM${NC}"
else
  echo -e "  ${YELLOW}[WARN] Revisa que /boot esté montado fuera de LVM/cifrado${NC}"
fi
echo ""

# 3. SSH Y PUERTO 4242
echo -e "${YELLOW}[3/8] Verificando SSH y Puerto 4242...${NC}"
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
  echo -e "  ${GREEN}[OK] El servicio SSH está activo${NC}"
else
  echo -e "  ${RED}[ERROR] El servicio SSH no está activo${NC}"
fi

if ss -tlnp | grep -q ":4242"; then
  echo -e "  ${GREEN}[OK] SSH está escuchando en el puerto 4242${NC}"
else
  echo -e "  ${RED}[ERROR] SSH NO está escuchando en el puerto 4242${NC}"
fi

if grep -Eq "^\s*PermitRootLogin\s+no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null; then
  echo -e "  ${GREEN}[OK] PermitRootLogin está configurado en 'no'${NC}"
else
  echo -e "  ${RED}[ERROR] PermitRootLogin NO está en 'no' en /etc/ssh/sshd_config${NC}"
fi
echo ""

# 4. FIREWALL (UFW)
echo -e "${YELLOW}[4/8] Verificando UFW (Cortafuegos)...${NC}"
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    echo -e "  ${GREEN}[OK] UFW está activo${NC}"
  else
    echo -e "  ${RED}[ERROR] UFW está instalado pero NO está activo${NC}"
  fi

  if ufw status | grep -q "4242"; then
    echo -e "  ${GREEN}[OK] El puerto 4242 está permitido en UFW${NC}"
  else
    echo -e "  ${RED}[ERROR] El puerto 4242 NO aparece permitido en UFW${NC}"
  fi
else
  echo -e "  ${RED}[ERROR] UFW no está instalado${NC}"
fi
echo ""

# 5. POLITICA DE SUDO
echo -e "${YELLOW}[5/8] Verificando Directivas de Sudo...${NC}"
SUDO_CONF=$(sudo visudo -c 2>&1)
if echo "$SUDO_CONF" | grep -q "parsed OK"; then
  echo -e "  ${GREEN}[OK] Sintaxis de /etc/sudoers es correcta${NC}"
else
  echo -e "  ${RED}[ERROR] Error de sintaxis en /etc/sudoers${NC}"
fi

if [ -d "/var/log/sudo" ]; then
  echo -e "  ${GREEN}[OK] El directorio /var/log/sudo existe${NC}"
else
  echo -e "  ${RED}[ERROR] El directorio /var/log/sudo NO existe${NC}"
fi

SUDO_FILES="/etc/sudoers /etc/sudoers.d/*"
check_sudo_def() {
  local pattern=$1
  local name=$2
  if grep -qsE "$pattern" $SUDO_FILES; then
    echo -e "  ${GREEN}[OK] Directiva '$name' configurada${NC}"
  else
    echo -e "  ${YELLOW}[WARN] Directiva '$name' no encontrada explícitamente en sudoers${NC}"
  fi
}

check_sudo_def "passwd_tries\s*=\s*3" "passwd_tries=3"
check_sudo_def "badpass_message" "badpass_message"
check_sudo_def "logfile\s*=\s*"/var/log/sudo/sudo.log"" "logfile=/var/log/sudo/sudo.log"
check_sudo_def "log_input" "log_input"
check_sudo_def "log_output" "log_output"
check_sudo_def "requiretty" "requiretty"
check_sudo_def "secure_path" "secure_path"
echo ""

# 6. POLITICA DE CONTRASEÑAS (PAM Y LOGIN.DEFS)
echo -e "${YELLOW}[6/8] Verificando Política de Contraseñas...${NC}"
grep -q "PASS_MAX_DAYS\s*30" /etc/login.defs && echo -e "  ${GREEN}[OK] PASS_MAX_DAYS = 30${NC}" || echo -e "  ${RED}[ERROR] PASS_MAX_DAYS no es 30${NC}"
grep -q "PASS_MIN_DAYS\s*2" /etc/login.defs && echo -e "  ${GREEN}[OK] PASS_MIN_DAYS = 2${NC}" || echo -e "  ${RED}[ERROR] PASS_MIN_DAYS no es 2${NC}"
grep -q "PASS_WARN_AGE\s*7" /etc/login.defs && echo -e "  ${GREEN}[OK] PASS_WARN_AGE = 7${NC}" || echo -e "  ${RED}[ERROR] PASS_WARN_AGE no es 7${NC}"

PAM_FILE="/etc/pam.d/common-password"
if grep -q "pam_pwquality.so" "$PAM_FILE"; then
  echo -e "  ${GREEN}[OK] Configuración pam_pwquality presente en common-password${NC}"
else
  echo -e "  ${RED}[ERROR] No se encontró pam_pwquality en $PAM_FILE${NC}"
fi
echo ""

# 7. APPARMOR
echo -e "${YELLOW}[7/8] Verificando AppArmor...${NC}"
if command -v aa-status >/dev/null 2>&1 && aa-status --enabled 2>/dev/null; then
  echo -e "  ${GREEN}[OK] AppArmor está activo y habilitado${NC}"
else
  echo -e "  ${RED}[ERROR] AppArmor no está activo o habilitado${NC}"
fi
echo ""

# 8. SCRIPT MONITORING.SH Y CRONTAB
echo -e "${YELLOW}[8/8] Verificando monitoring.sh y Cron...${NC}"
MON_SCRIPT="/usr/local/bin/monitoring.sh"
if [ -f "$MON_SCRIPT" ] && [ -x "$MON_SCRIPT" ]; then
  echo -e "  ${GREEN}[OK] Archivo $MON_SCRIPT existe y es ejecutable (+x)${NC}"
else
  echo -e "  ${RED}[ERROR] Falta el archivo $MON_SCRIPT o no tiene permisos de ejecución${NC}"
fi

if crontab -l 2>/dev/null | grep -q "monitoring.sh"; then
  echo -e "  ${GREEN}[OK] Regla de cron para monitoring.sh presente en crontab de root${NC}"
else
  echo -e "  ${RED}[ERROR] No se encontró la regla en el crontab de root${NC}"
fi

echo -e "${BLUE}======================================================"${NC}
echo -e "${BLUE}              FIN DE LA COMPROBACIÓN                  "${NC}
echo -e "${BLUE}======================================================"${NC}
```

---

## 📚 Preguntas Teóricas Esenciales para la Defensa

Durante la corrección entre pares (*peer-evaluation*), el evaluador te formulará preguntas conceptuales. Aquí tienes el resumen defensivo clave:

1. **Debian vs. Rocky Linux:**
   * **Debian:** Distribución basada en la comunidad que usa paquetes `.deb` (`apt`). Es ligera, extremadamente estable y utiliza **AppArmor** como sistema de seguridad por defecto.
   * **Rocky Linux:** Distribución orientada a entornos empresariales basada en RHEL. Usa paquetes `.rpm` (`dnf`/`yum`) y utiliza **SELinux** por defecto.

2. **AppArmor vs. SELinux:**
   * **AppArmor:** Control de acceso obligatorio (MAC) que asocia los perfiles de seguridad directamente a las **rutas de los archivos ejecutable**. Es más sencillo de administrar.
   * **SELinux:** Sistema MAC que asigna **etiquetas y contextos de seguridad** a cada proceso, usuario y archivo (inodes). Permite un control extremadamente fino pero con mayor complejidad.

3. **UFW vs. firewalld:**
   * **UFW (Uncomplicated Firewall):** Interfaz simplificada sobre `iptables`/`nftables` predeterminada en Debian.
   * **firewalld:** Demonio de gestión dinámica del cortafuegos por zonas habitual en distribuciones RHEL/Rocky Linux.

4. **VirtualBox vs. UTM:**
   * **VirtualBox:** Hipervisor de tipo 2 multiplataforma para arquitecturas x86/x64 (Intel/AMD).
   * **UTM:** Hipervisor optimizado para macOS que aprovecha el motor de virtualización nativo de Apple Silicon (M1/M2/M3) mediante QEMU.

5. **`apt` vs. `aptitude`:**
   * **`apt`:** Herramienta estándar de línea de comandos para la gestión básica e interactiva de paquetes.
   * **`aptitude`:** Gestor avanzado que incluye interfaz de texto (ncurses) y un algoritmo superior para resolver conflictos complejos de dependencias.

6. **LVM y Cifrado LUKS:**
   * **LVM (Logical Volume Manager):** Capa de abstracción entre los discos físicos y los sistemas de archivos. Permite crear y redimensionar volúmenes lógicos dinámicamente sin desmontar el sistema.
   * **LUKS (Linux Unified Key Setup):** Estándar de cifrado de bloque en Linux. Cifra la partición física (`sda5_crypt`) sobre la que se asienta el grupo de volúmenes LVM.

---

## 🛠️ Comandos Prácticos para la Evaluación en Vivo

El evaluador te pedirá realizar demostraciones en la consola de tu Debian:

* **Cambiar el Hostname:**
  ```bash
  sudo hostnamectl set-hostname nuevo_nombre42
  # Restaurar:
  sudo hostnamectl set-hostname <tu_login>42
  ```
* **Crear un Usuario y asignarlo al grupo `user42`:**
  ```bash
  sudo adduser nuevo_usuario
  sudo usermod -aG user42 nuevo_usuario
  groups nuevo_usuario
  ```
* **Detener / Pausar `monitoring.sh` sin modificar el script:**
  ```bash
  # Opción 1: Comentar la línea en crontab
  sudo crontab -e
  # Opción 2: Matar el proceso en ejecución
  pkill -f monitoring.sh
  ```
* **Verificar el particionado LVM cifrado:**
  ```bash
  lsblk
  sudo vgs
  sudo lvs
  sudo cryptsetup status sda5_crypt
  ```
* **Consultar el registro de auditoría de Sudo:**
  ```bash
  sudo cat /var/log/sudo/sudo.log
  ```

---

## 📦 Instrucciones de Entrega y Firma SHA1 (`signature.txt`)

1. **Apaga la VM por completo:** `sudo shutdown now`.
2. **Genera la firma SHA1** en la terminal de tu ordenador anfitrión (Host):
   * En Mac / Linux:
     ```bash
     shasum tu_maquina.vdi > signature.txt
     ```
3. **Sube únicamente los archivos de documentación:**
   * `signature.txt`
   * `README.md`
   *(🛑 Nunca subas el archivo `.vdi` al repositorio de Git)*.

---
*Created as part of the 42 Born2BeRoot curriculum.*
