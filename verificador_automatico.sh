#!/bin/bash
# Shebang: define el intérprete Bash para la ejecución del script

# ==============================================================================
# Script de Comprobación de Requisitos - Born2BeRoot (42)
# Ejecutar en Debian con: sudo bash check_born2beroot.sh
# ==============================================================================

# Definición de códigos ANSI para salida con color
GREEN='\033[0;32m'   # Verde para checks correctos
RED='\033[0;31m'     # Rojo para errores o requisitos no cumplidos
YELLOW='\033[1;33m'  # Amarillo para títulos y advertencias
BLUE='\033[0;34m'    # Azul para bordes y encabezados
NC='\033[0m'         # No Color: resetea el formato de la terminal

# Banner inicial del script
echo -e "${BLUE}======================================================"${NC}
echo -e "${BLUE} VERIFICADOR DE REQUISITOS BORN2BEROOT (42) "${NC}
echo -e "${BLUE}======================================================"${NC}
echo ""

# Comprueba si el usuario tiene privilegios de superusuario (UID 0)
if [ "$EUID" -ne 0 ]; then
    # Muestra error si no se ejecuta como root y detiene el script
    echo -e "${RED}[ERROR] Este script debe ejecutarse como root (sudo bash check_born2beroot.sh)${NC}"
    exit 1
fi

# 1. HOSTNAME
echo -e "${YELLOW}[1/8] Verificando Hostname...${NC}"
# Guarda el hostname de la máquina en una variable
HOSTNAME=$(hostname)
# Valida mediante regex que el hostname termine en "42" (ej. login42)
if [[ "$HOSTNAME" =~ 42$ ]]; then
    echo -e " ${GREEN}[OK] Hostname es '$HOSTNAME' (termina en 42)${NC}"
else
    echo -e " ${RED}[ERROR] Hostname es '$HOSTNAME' (NO termina en 42)${NC}"
fi
echo ""

# 2. CIFRADO LUKS Y LVM
echo -e "${YELLOW}[2/8] Verificando LVM y Cifrado LUKS...${NC}"
# Revisa con blkid si existe alguna partición de tipo crypto_LUKS
if blkid | grep -q "crypto_LUKS"; then
    echo -e " ${GREEN}[OK] Partición cifrada LUKS detectada${NC}"
else
    echo -e " ${RED}[ERROR] No se detectó ninguna partición cifrada LUKS (crypto_LUKS)${NC}"
fi

# Cuenta el número de volúmenes o particiones de tipo lvm en lsblk
LVM_COUNT=$(lsblk | grep -c "lvm")
# Requiere al menos 2 volúmenes LVM configurados
if [ "$LVM_COUNT" -ge 2 ]; then
    echo -e " ${GREEN}[OK] Se detectaron volúmenes LVM ($LVM_COUNT LVs)${NC}"
else
    echo -e " ${RED}[ERROR] Se encontraron menos de 2 volúmenes LVM ($LVM_COUNT encontrados)${NC}"
fi
echo ""

# 3. SSH Y PUERTO 4242
echo -e "${YELLOW}[3/8] Verificando SSH y Puerto 4242...${NC}"
# Comprueba si el servicio SSH está activo (nombre 'ssh' en Debian o 'sshd')
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    echo -e " ${GREEN}[OK] El servicio SSH está activo${NC}"
else
    echo -e " ${RED}[ERROR] El servicio SSH no está activo${NC}"
fi

# Comprueba si algún proceso escucha en TCP en el puerto 4242
if ss -tlnp | grep -q ":4242"; then
    echo -e " ${GREEN}[OK] SSH está escuchando en el puerto 4242${NC}"
else
    echo -e " ${RED}[ERROR] SSH NO está escuchando en el puerto 4242${NC}"
fi

# Busca la directiva PermitRootLogin deshabilitada (no comentada) en la config de SSH
if grep -Eq "^\s*PermitRootLogin\s+no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null; then
    echo -e " ${GREEN}[OK] PermitRootLogin está configurado en 'no'${NC}"
else
    echo -e " ${RED}[ERROR] PermitRootLogin NO está en 'no' en /etc/ssh/sshd_config${NC}"
fi
echo ""

# 4. FIREWALL (UFW)
echo -e "${YELLOW}[4/8] Verificando UFW (Cortafuegos)...${NC}"
# Verifica que el binario de UFW exista en el sistema
if command -v ufw >/dev/null 2>&1; then
    # Comprueba que el firewall esté activo
    if ufw status | grep -q "Status: active"; then
        echo -e " ${GREEN}[OK] UFW está activo${NC}"
    else
        echo -e " ${RED}[ERROR] UFW está instalado pero NO está activo${NC}"
    fi

    # Comprueba que exista una regla permitiendo el tráfico al puerto 4242
    if ufw status | grep -q "4242"; then
        echo -e " ${GREEN}[OK] El puerto 4242 está permitido en UFW${NC}"
    else
        echo -e " ${RED}[ERROR] El puerto 4242 NO aparece permitido en UFW${NC}"
    fi
else
    echo -e " ${RED}[ERROR] UFW no está instalado${NC}"
fi
echo ""

# 5. POLITICA DE SUDO
echo -e "${YELLOW}[5/8] Verificando Directivas de Sudo...${NC}"
# Comprueba que exista el directorio obligatorio para logs de sudo
if [ -d "/var/log/sudo" ]; then
    echo -e " ${GREEN}[OK] El directorio /var/log/sudo existe${NC}"
else
    echo -e " ${RED}[ERROR] El directorio /var/log/sudo NO existe${NC}"
fi

# Archivos de sudoers donde buscar las directivas
SUDO_FILES="/etc/sudoers /etc/sudoers.d/*"

# Función auxiliar para comprobar directivas específicas en sudoers
check_sudo_def() {
    local pattern=$1  # Patrón regex a buscar
    local name=$2     # Nombre representativo para el mensaje
    if grep -qsE "$pattern" $SUDO_FILES; then
        echo -e " ${GREEN}[OK] Directiva '$name' configurada${NC}"
    else
        echo -e " ${YELLOW}[WARN] Directiva '$name' no encontrada explícitamente en sudoers${NC}"
    fi
}

# Verificación de directivas requeridas en el archivo de sudoers
check_sudo_def "passwd_tries\s*=\s*3" "passwd_tries=3"                               # Máximo 3 intentos de contraseña
check_sudo_def "badpass_message" "badpass_message"                                   # Mensaje de error personalizado
check_sudo_def "logfile\s*=\s*\"/var/log/sudo/sudo.log\"" "logfile=/var/log/sudo/sudo.log" # Ruta del log de sudo
check_sudo_def "log_input" "log_input"                                               # Registro de entrada (comandos)
check_sudo_def "log_output" "log_output"                                             # Registro de salida
check_sudo_def "requiretty" "requiretty"                                             # Obliga ejecución desde TTY
check_sudo_def "secure_path" "secure_path"                                           # PATH restringido para root
echo ""

# 6. POLITICA DE CONTRASEÑAS (PAM Y LOGIN.DEFS)
echo -e "${YELLOW}[6/8] Verificando Política de Contraseñas...${NC}"
# Verifica caducidad máxima de contraseñas (30 días)
grep -q "PASS_MAX_DAYS\s*30" /etc/login.defs && echo -e " ${GREEN}[OK] PASS_MAX_DAYS = 30${NC}" || echo -e " ${RED}[ERROR] PASS_MAX_DAYS no es 30${NC}"
# Verifica días mínimos entre cambios de contraseña (2 días)
grep -q "PASS_MIN_DAYS\s*2" /etc/login.defs && echo -e " ${GREEN}[OK] PASS_MIN_DAYS = 2${NC}" || echo -e " ${RED}[ERROR] PASS_MIN_DAYS no es 2${NC}"
# Verifica aviso de expiración (7 días de antelación)
grep -q "PASS_WARN_AGE\s*7" /etc/login.defs && echo -e " ${GREEN}[OK] PASS_WARN_AGE = 7${NC}" || echo -e " ${RED}[ERROR] PASS_WARN_AGE no es 7${NC}"

# Ruta del fichero PAM para complejidad de contraseñas
PAM_FILE="/etc/pam.d/common-password"
# Comprueba que el módulo pam_pwquality esté configurado en PAM
if grep -q "pam_pwquality.so" "$PAM_FILE"; then
    echo -e " ${GREEN}[OK] Configuración pam_pwquality presente en common-password${NC}"
else
    echo -e " ${RED}[ERROR] No se encontró pam_pwquality en $PAM_FILE${NC}"
fi
echo ""

# 7. APPARMOR
echo -e "${YELLOW}[7/8] Verificando AppArmor...${NC}"
# Verifica que el comando aa-status exista y que AppArmor esté activo
if command -v aa-status >/dev/null 2>&1 && aa-status --enabled 2>/dev/null; then
    echo -e " ${GREEN}[OK] AppArmor está activo y habilitado${NC}"
else
    echo -e " ${RED}[ERROR] AppArmor no está activo o habilitado${NC}"
fi
echo ""

# 8. SCRIPT MONITORING.SH Y CRONTAB
echo -e "${YELLOW}[8/8] Verificando monitoring.sh y Cron...${NC}"
MON_SCRIPT="/usr/local/bin/monitoring.sh"
# Comprueba que el script de monitorización exista y tenga permisos de ejecución (+x)
if [ -f "$MON_SCRIPT" ] && [ -x "$MON_SCRIPT" ]; then
    echo -e " ${GREEN}[OK] Archivo $MON_SCRIPT existe y es ejecutable (+x)${NC}"
else
    echo -e " ${RED}[ERROR] Falta el archivo $MON_SCRIPT o no tiene permisos de ejecución${NC}"
fi

# Verifica que exista una entrada para el script en el crontab de root
if crontab -l 2>/dev/null | grep -q "monitoring.sh"; then
    echo -e " ${GREEN}[OK] Regla de cron para monitoring.sh presente en crontab de root${NC}"
else
    echo -e " ${RED}[ERROR] No se encontró la regla en el crontab de root${NC}"
fi

# Banner final
echo -e "${BLUE}======================================================"${NC}
echo -e "${BLUE} FIN DE LA COMPROBACIÓN "${NC}
echo -e "${BLUE}======================================================"${NC}
