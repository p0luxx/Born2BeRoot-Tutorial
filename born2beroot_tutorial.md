# Born2beRoot — Tutorial paso a paso

> Guía práctica para completar el proyecto. Usa Debian como ejemplo (es la opción más común y con más documentación en español/inglés), pero se indican las diferencias con Rocky Linux cuando aplican.

---

## 0. Antes de empezar: entiende qué vas a construir

Born2beRoot te pide levantar una VM Linux "endurecida" (hardened): particionado con LVM, SSH solo por usuario (no root) en el puerto 4242, firewall restrictivo, política de contraseñas estricta, sudo muy limitado y auditado, y un script `monitoring.sh` que informa del estado del sistema cada 10 minutos.

Cosas que **debes poder explicar en la defensa**:
- Diferencia entre `apt` y `aptitude` (ambos son gestores de paquetes; `apt` es más moderno y pensado para uso interactivo simple, `aptitude` tiene resolución de dependencias más avanzada e interfaz de texto).
- Qué es **AppArmor** (Debian: control de acceso obligatorio basado en rutas de archivo, perfiles por programa) vs **SELinux** (Rocky: control de acceso obligatorio basado en etiquetas/contextos, más granular y más complejo).
- Qué es **LVM** (Logical Volume Manager: capa de abstracción que permite redimensionar particiones "en caliente", crear snapshots, etc.).

---

## 1. Instalar el hipervisor y crear la VM

1. Instala **VirtualBox** (o **UTM** si usas Mac con Apple Silicon).
2. Descarga la ISO de **Debian** (netinst) o **Rocky Linux** desde su web oficial.
3. Crea una nueva VM:
   - Tipo: Linux, versión: Debian (64-bit) o Red Hat (64-bit).
   - RAM: 1024 MB suele bastar.
   - Disco duro: crea un disco virtual **VDI** (o QCOW2 en UTM), tamaño dinámico, ~8-10 GB.
4. En la configuración de red de la VM, dependiendo del hipervisor, usa NAT o Bridged (necesitas que la VM tenga IP para SSH).
5. Monta la ISO como unidad óptica e inicia la VM.

---

## 2. Instalación del sistema operativo (con particionado manual)

Durante el instalador:

1. Elige idioma, teclado, hostname → **debe ser tu login terminado en 42** (ej. `wil42`).
2. Crea un usuario **no-root** cuyo username sea tu login. Este usuario luego deberá pertenecer a los grupos `user42` y `sudo`.
3. Cuando llegues al particionado, elige **"Manual"** (no uses el guiado automático) y configura **LVM cifrado**:
   - Crea una partición `/boot` **fuera de LVM y sin cifrar** (ej. 500 MB, tipo ext2/ext4). Es obligatoria porque GRUB no siempre puede leer LVM ni particiones cifradas directamente.
   - Crea una partición física grande (el resto del disco) y márcala como **"physical volume for encryption"** (no "for LVM" todavía).
   - Configura el **volumen cifrado**: el instalador te preguntará si quieres sobrescribir el disco con datos aleatorios (puedes omitirlo en una VM para ir más rápido) y luego te pedirá una **passphrase**. Esta contraseña te la pedirá la VM **cada vez que arranque**, antes incluso de llegar al login — apúntala, es distinta de la contraseña de tu usuario o de root.
   - Una vez creado el volumen cifrado (aparecerá como algo tipo `sda5_crypt`), entra en él y **ahora sí** márcalo como **"physical volume for LVM"**.
   - Sobre ese physical volume (ya cifrado), crea un **volume group** (ej. `vg_data`).
   - Dentro del VG, crea **logical volumes** (particiones lógicas) separadas, por ejemplo:
     - `/` (root) — 2-3 GB
     - `/home` — 1-2 GB
     - `/var` — 2 GB (importante: aquí van los logs de sudo)
     - `/var/log` — 1 GB (opcional, separarlo es buena práctica de seguridad)
     - `swap` — igual o el doble de tu RAM si tienes poca RAM (con 1GB de RAM, un swap de 1-2GB está bien)
   - No sobre-dimensiones: deja algo de espacio libre en el VG si quieres margen, pero no desperdicies disco.

   > **Importante:** el subject exige *"al menos 2 particiones cifradas usando LVM"*. Con este esquema, todo el volumen físico está cifrado con LUKS **antes** de la capa LVM, así que **todos los logical volumes que crees dentro (`/`, `/home`, `/var`, swap, etc.) quedan cifrados automáticamente** — con eso ya cumples de sobra el mínimo de 2. No necesitas cifrar cada LV por separado.
   - Verifica después de instalar con `lsblk` que aparece una línea de tipo `crypt` entre la partición física y los `lvm` (ver el ejemplo del PDF: `sda5` → `sda5_crypt` → `vg-root`, `vg-swap`, `vg-home`).
4. Instala solo lo mínimo: **no instales entorno gráfico**, ni servidor web, ni impresión. Solo "SSH server" y "utilidades estándar del sistema" si el instalador te lo pregunta.
5. Instala GRUB en el disco (MBR) cuando lo pida.
6. Termina la instalación y reinicia.

---

## 3. Primeros pasos tras instalar

Entra como root o con tu usuario + `su`:

```bash
apt update && apt upgrade -y
apt install sudo -y
```

Verifica que LVM está activo:
```bash
lsblk
sudo lvdisplay
```

Verifica también que el cifrado está activo (debe listarte tu volumen LUKS):
```bash
sudo cryptsetup status sda5_crypt   # ajusta el nombre al que te haya puesto el instalador
sudo blkid | grep crypto_LUKS
```
Si esto no devuelve nada, significa que no cifraste el volumen durante la instalación y **tendrás que reinstalar el sistema** (el cifrado LUKS no se puede añadir a una partición LVM ya creada sin perder los datos, así que revisa este punto cuanto antes).

---

## 4. Configurar sudo correctamente

Añade tu usuario a los grupos `sudo` y `user42`:
```bash
groupadd user42          # si no existe
usermod -aG sudo,user42 tu_login
```

Edita la configuración de sudo con `visudo` (nunca edites `/etc/sudoers` a mano con otro editor):
```bash
sudo visudo
```

Añade estas líneas (ajusta al final del archivo, o mejor, crea un archivo dedicado en `/etc/sudoers.d/`):

```
Defaults        passwd_tries=3
Defaults        badpass_message="Contraseña incorrecta. Inténtalo de nuevo."
Defaults        logfile="/var/log/sudo/sudo.log"
Defaults        log_input,log_output
Defaults        iolog_dir="/var/log/sudo"
Defaults        requiretty
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
```

Crea la carpeta de logs:
```bash
sudo mkdir -p /var/log/sudo
```

Explicación rápida:
- `passwd_tries=3`: máximo 3 intentos.
- `badpass_message`: mensaje personalizado si te equivocas.
- `log_input,log_output` + `iolog_dir`: registra todo lo que escribes y ves al usar sudo (para auditoría).
- `requiretty`: obliga a que sudo se ejecute desde una TTY real (más seguro).
- `secure_path`: restringe qué carpetas se usan para buscar comandos ejecutados con sudo (evita ataques de PATH).

---

## 5. Configurar SSH (puerto 4242, sin root)

Edita `/etc/ssh/sshd_config`:
```bash
sudo nano /etc/ssh/sshd_config
```

Cambia/asegura estas líneas:
```
Port 4242
PermitRootLogin no
PasswordAuthentication yes
```

Reinicia el servicio:
```bash
sudo systemctl restart ssh
sudo systemctl enable ssh
```

Prueba desde fuera (o desde el host) conectando:
```bash
ssh tu_login@IP_DE_LA_VM -p 4242
```

---

## 6. Configurar el firewall

### Debian (UFW)
```bash
sudo apt install ufw -y
sudo ufw allow 4242
sudo ufw enable
sudo ufw status
sudo systemctl enable ufw
```

### Rocky (firewalld)
```bash
sudo dnf install firewalld -y
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-port=4242/tcp
sudo firewall-cmd --permanent --remove-service=ssh   # quita el puerto 22 por defecto si estaba abierto
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

El firewall **debe estar activo al arrancar la VM** — con `enable` ya queda cubierto.

### Nota específica para Rocky: SELinux + puerto 4242

El subject exige que **SELinux esté activo (`enforcing`) al arranque** y que su configuración esté **adaptada a las necesidades del proyecto** — no basta con dejarlo en modo por defecto sin tocarlo si algo choca con tus cambios (por ejemplo, sshd escuchando en un puerto no estándar).

```bash
sestatus                       # comprueba que "Current mode: enforcing"
sudo semanage port -l | grep ssh_port_t     # ver puertos permitidos para sshd
sudo semanage port -a -t ssh_port_t -p tcp 4242   # autoriza el 4242 para el contexto ssh
sudo systemctl restart sshd
```

Sin ese `semanage port -a`, SELinux puede bloquear que sshd escuche en el 4242 aunque el firewall lo permita, y el servicio fallará o no arrancará correctamente — es un fallo típico y silencioso en Rocky. El subject aclara que **no hace falta configurar KDump** en Rocky (se te exime explícitamente de ese punto), pero SELinux sí debe quedar activo y coherente con tu configuración.

---

## 7. Política de contraseñas fuerte

Instala las herramientas necesarias:
```bash
sudo apt install libpam-pwquality -y
```

### 7.1 Caducidad de contraseñas — `/etc/login.defs`
```bash
sudo nano /etc/login.defs
```
Ajusta:
```
PASS_MAX_DAYS   30
PASS_MIN_DAYS   2
PASS_WARN_AGE   7
```

Esto solo afecta a usuarios nuevos; para aplicarlo a los existentes (root y tu usuario):
```bash
sudo chage -M 30 -m 2 -W 7 root
sudo chage -M 30 -m 2 -W 7 tu_login
```

### 7.2 Complejidad — `/etc/pam.d/common-password` (Debian)
Busca la línea que empieza con `password requisite pam_pwquality.so` y ajústala (o añádela):
```
password requisite pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 reject_username difok=7 enforce_for_root
```

Explicación de cada opción:
- `minlen=10`: mínimo 10 caracteres.
- `ucredit=-1`: al menos 1 mayúscula.
- `lcredit=-1`: al menos 1 minúscula.
- `dcredit=-1`: al menos 1 número.
- `maxrepeat=3`: no más de 3 caracteres idénticos consecutivos.
- `reject_username`: la contraseña no puede contener el nombre de usuario.
- `difok=7`: al menos 7 caracteres deben ser distintos de la contraseña anterior.
- `enforce_for_root`: hace que PAM también valide la contraseña de root contra esta política (por defecto root está exento).

> **Matiz importante para la defensa:** el subject dice explícitamente que la regla de "al menos 7 caracteres distintos de la anterior" (`difok=7`) **no aplica a la contraseña de root**, pero el resto de reglas (longitud, mayúscula/minúscula/número, `maxrepeat`, `reject_username`) sí. PAM no permite excluir una sola opción solo para root dentro de la misma línea `pam_pwquality.so`, así que en la práctica hay dos enfoques aceptados:
> 1. **El más simple (y el que usa la mayoría):** dejar `enforce_for_root` con todas las opciones, incluido `difok`, y en el README/defensa explicar que eres consciente de la excepción del subject pero que técnicamente PAM aplica la regla de forma global; si te preguntan, sabes justificarlo.
> 2. **El más estricto:** quitar `difok=7` de la línea genérica (dejarla en el resto de reglas + `enforce_for_root`) y forzar `difok` solo para usuarios normales mediante una regla condicional en `/etc/pam.d/common-password` (más complejo, no es obligatorio para aprobar).
>
> Lo importante en la defensa no es cuál elijas, sino que **puedas explicar por qué** el subject hace esa excepción y qué opción tomaste tú.

Después de configurar todo esto, **cambia la contraseña de root y de tu usuario** para que se apliquen realmente las reglas:
```bash
sudo passwd root
sudo passwd tu_login
```

---

## 8. Crear el script `monitoring.sh`

Este script se ejecuta al arranque y cada 10 minutos vía cron, mostrando info del sistema con `wall`.

```bash
sudo nano /usr/local/bin/monitoring.sh
```

Contenido (ejemplo funcional, coméntalo y entiéndelo, no lo copies sin más):

```bash
#!/bin/bash

# Arquitectura y kernel
arch=$(uname -a)

# CPU físicas
pcpu=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)

# CPU virtuales
vcpu=$(grep -c ^processor /proc/cpuinfo)

# Memoria
mem_total=$(free -m | awk '$1=="Mem:"{print $2}')
mem_used=$(free -m | awk '$1=="Mem:"{print $3}')
mem_percent=$(echo "scale=2; $mem_used*100/$mem_total" | bc)

# Disco
disk_total=$(df -BG --total 2>/dev/null | grep total | awk '{print $2}' | sed 's/G//')
disk_used=$(df -BG --total 2>/dev/null | grep total | awk '{print $3}' | sed 's/G//')
disk_percent=$(df --total 2>/dev/null | grep total | awk '{print $5}')

# CPU load
cpu_load=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')

# Último boot
last_boot=$(who -b | awk '{print $3, $4}')

# LVM
lvm_use=$(lsblk 2>/dev/null | grep -c "lvm")
if [ "$lvm_use" -gt 0 ]; then lvm_use="yes"; else lvm_use="no"; fi

# Conexiones TCP activas
tcp_con=$(ss -ta | grep ESTAB | wc -l)

# Usuarios conectados
log_users=$(who | wc -l)

# Red
ip_addr=$(hostname -I | awk '{print $1}')
mac_addr=$(ip link | grep "link/ether" | awk '{print $2}')

# Sudo
sudo_cmd=$(journalctl _COMM=sudo 2>/dev/null | grep COMMAND | wc -l)

wall "
Architecture: $arch
Physical CPU: $pcpu
vCPU: $vcpu
Memory Usage: $mem_used/${mem_total}MB ($mem_percent%)
Disk Usage: $disk_used/${disk_total}Gb ($disk_percent)
CPU load: $cpu_load%
Last boot: $last_boot
LVM use: $lvm_use
TCP Connections: $tcp_con ESTABLISHED
User log: $log_users
Network: IP $ip_addr ($mac_addr)
Sudo: $sudo_cmd cmd"
```

Dale permisos de ejecución:
```bash
sudo chmod +x /usr/local/bin/monitoring.sh
```

Pruébalo manualmente:
```bash
sudo /usr/local/bin/monitoring.sh
```

---

## 9. Ejecutar el script cada 10 minutos y al arranque (cron)

Edita el crontab de root:
```bash
sudo crontab -e
```

Añade:
```
*/10 * * * * /usr/local/bin/monitoring.sh
@reboot sleep 30 && /usr/local/bin/monitoring.sh
```

(el `sleep 30` en el reboot da tiempo a que el sistema arranque completamente antes de que `wall` intente escribir en las terminales).

Para interrumpir el script en marcha sin modificarlo (te lo pedirán en la defensa): puedes usar `Ctrl+C` si lo lanzas en foreground, o `pkill -f monitoring.sh` / matar el PID con `kill` si corre en background.

---

## 10. Comprobaciones antes de la defensa

Checklist rápido:
- [ ] `hostname` termina en 42.
- [ ] `ssh usuario@ip -p 4242` funciona; `ssh root@ip -p 4242` **falla**.
- [ ] `sudo ufw status` (o `firewall-cmd --list-all`) muestra solo el 4242 abierto.
- [ ] `sudo -l` muestra tus restricciones de sudo aplicadas.
- [ ] `chage -l tu_login` muestra la política de caducidad correcta.
- [ ] Intentar poner una contraseña débil falla (prueba con `passwd`).
- [ ] `/var/log/sudo/` contiene logs tras usar sudo.
- [ ] `monitoring.sh` se ejecuta correctamente y sin errores.
- [ ] `lsblk` / `sudo vgs` / `sudo lvs` muestran tu esquema de LVM.
- [ ] `sudo cryptsetup status <nombre>` confirma que el volumen está cifrado (LUKS activo).
- [ ] **No hay ningún snapshot** en la VM antes de empezar la evaluación (el subject lo prohíbe explícitamente; solo se crea uno dedicado a la defensa y se borra al terminar).
- [ ] La passphrase de cifrado del disco la tienes apuntada y la recuerdas — se pide al arrancar la VM, antes del login.

### Cosas que te van a pedir literalmente durante la evaluación (no solo comprobar)

Estas no son solo checks tuyos, son acciones que el evaluador puede pedirte hacer en directo:
- **Cambiar el hostname** de la VM (debe seguir terminando en 42).
- **Crear un usuario nuevo** y asignarlo a un grupo, para probar que entiendes la gestión de usuarios/SSH.
- **Interrumpir `monitoring.sh` sin modificar el script** (piensa en `crontab -e` para comentar/quitar temporalmente la línea, o matar el proceso si está corriendo en ese momento — no vale editar el `.sh`).
- Explicar **diferencias conceptuales**: `apt` vs `aptitude`, AppArmor vs SELinux, UFW vs firewalld, y (si aplica) VirtualBox vs UTM.
- Posiblemente una **pequeña modificación en vivo** del proyecto (una línea de script, un campo nuevo en el monitoring, etc.) — se especifica en la guía de evaluación de tu turno, no siempre aplica.

---

## 11. README.md y signature.txt

En la raíz del repo Git:

**README.md** debe incluir, como mínimo:
1. Primera línea en cursiva: `*This project has been created as part of the 42 curriculum by <login>.*`
2. Sección **Description**: qué es el proyecto y su objetivo.
3. Sección **Instructions**: cómo instalar/ejecutar.
4. Sección **Resources**: enlaces de referencia + explicación de cómo usaste IA (para qué tareas concretas).
5. Sección de elección de SO: por qué Debian o Rocky, ventajas/desventajas, y comparativas:
   - Debian vs Rocky Linux
   - AppArmor vs SELinux
   - UFW vs firewalld
   - VirtualBox vs UTM

**signature.txt**: apaga la VM (o snapshot solo para evaluación) y calcula el hash SHA1 del disco virtual:
```bash
# Linux
sha1sum tu_vm.vdi
# Windows
certUtil -hashfile tu_vm.vdi sha1
# macOS
shasum tu_vm.vdi
```
Copia el resultado en `signature.txt`. **Nunca subas la VM al repo**, solo el hash.

---

## 12. Bonus (solo si el mandatory está perfecto)

- Particionado más granular (más logical volumes).
- WordPress funcional con **lighttpd + MariaDB + PHP** (nginx/apache2 prohibidos).
- Un servicio adicional a tu elección (justificable en la defensa).
- Si abres más puertos para los servicios bonus, actualiza UFW/firewalld en consecuencia.

---

### Resumen mental para la defensa
Tienes que poder explicar **por qué** hiciste cada cosa, no solo copiar comandos: por qué LVM, por qué separar `/var`, qué hace cada línea de `sudoers`, cómo interrumpirías el cron sin tocar el script, y las diferencias conceptuales entre las herramientas comparadas en el README.
