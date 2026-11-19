# Seagate Constellation ES.3 mit Dell-OEM-Firmware (ST1000NM0033 und verwandte Modelle): Firmware-Update auf GA10 auf einem Linux-Server, der nicht von Dell stammt

**Inoffizielle Community-Anleitung.** Hier wird keine Firmware verteilt: Das Originalpaket laden Sie selbst von Dell herunter.

Sprachen: [English](README.md) | [Українська](README.uk.md) | **Deutsch**

---

## Worum es geht

Seagate-Constellation-ES.3-SATA-Festplatten mit Dell-Kennung (`Add. Product Id: DELL(tm)`, Firmware `GA0x`) landen oft in Rechnern anderer Hersteller: in gemieteten Dedicated-Servern, in aufbereiteter Hardware, im Homelab. Dell hat für diese Platten eine neuere Firmware veröffentlicht, **GA10**, aber:

- Dells Update-Paket verweigert auf Nicht-Dell-Hardware den Dienst (`Can't open IPMI device`, „not compatible with your system configuration“).
- Seagates eigene Firmware (`SN0x`) ist für Retail-Platten gedacht und darf nicht auf Dell-OEM-Platten eingespielt werden.

Diese Anleitung zeigt, wie man das Firmware-Image aus Dells Paket holt, den Dell-Header entfernt, das Ergebnis prüft und es mit `hdparm` einspielt. Jeder Befehl unten wurde auf einem echten Server ausgeführt.

## Getestete Konfiguration

| Punkt | Wert |
|---|---|
| Server | HP ProLiant DL120 G7, Onboard-SATA-Controller (Platten erscheinen als normale `/dev/sdX`) |
| Betriebssystem | CentOS 7, Kernel 3.10.0-1062 (x86_64), Plesk |
| Werkzeuge | hdparm 9.43, smartmontools 7.0 |
| Platten | 4 × Seagate `ST1000NM0033-9ZM173`, Dell OEM |
| Firmware vorher | `GA06` (2 Platten), `GA0A` (2 Platten) |
| Firmware nachher | `GA10` (alle 4 Platten) |
| Datum | 19.11.2026 |

Ergebnis: Alle vier Platten haben das Image beim ersten Versuch angenommen. Die neue Version war sofort aktiv, ohne Neustart und ohne Aus- und Einschalten. Drei Platten wurden ausgehängt geflasht; die Systemplatte (Boot und Root) wurde geflasht, während das Betriebssystem von ihr lief. Danach meldete SMART `PASSED`, und die kurzen Selbsttests liefen auf allen vier Platten fehlerfrei durch.

## Passt die Anleitung zu Ihrer Platte?

Führen Sie `smartctl -i /dev/sdX` aus (oder `scripts/list-drives.sh`). Die Anleitung passt nur, wenn **alles** davon zutrifft:

1. `Device Model` ist eines von
   `ST4000NM0033-9ZM170`, `ST3000NM0033-9ZM178`, `ST2000NM0033-9ZM175`, `ST1000NM0033-9ZM173`, `ST500NM0003-9ZM172`
2. `Add. Product Id` lautet `DELL(tm)`
3. `Firmware Version` beginnt mit `GA0` (zum Beispiel `GA06`, `GA0A`, `GA0D`, `GA0F`)
4. Die Platte hängt direkt an einem SATA/AHCI-Port, sodass `hdparm` sie ansprechen kann

Tatsächlich getestet wurde nur `ST1000NM0033-9ZM173`. Die anderen vier Modelle stehen im Header derselben Firmware-Datei und auf Dells Download-Seite, wurden hier aber von niemandem geflasht.

Die Anleitung passt **nicht** für:

| Platte | Was stattdessen zu tun ist |
|---|---|
| Dell-Platten mit Firmware `GA6x` (die 6-Gbit/s-Variante) | Für diese nennt Dell `GA6E`, das ist ein anderes Paket (Driver ID `72RV5`). GA10 dort nicht einspielen. |
| Retail-Platten mit Firmware `SN0x` | Die Firmware von der Seagate-Website verwenden. |
| SAS-Modelle (`ST…NM0023`, Firmware `GSxx`) | Andere Firmware und andere Werkzeuge. |
| Platten hinter einem Hardware-RAID-Controller (PERC, Smart Array, MegaRAID) | Nicht getestet. `hdparm` erreicht solche Platten in der Regel nicht. |

## Warum überhaupt aktualisieren

- Dells Versionshinweise zu GA10 nennen eine Korrektur für die ungenaue Zählung von SMART-Suchfehlern, die SMART unerwartet auslösen konnte, sowie allgemeine Verbesserungen der Robustheit.
- Der Dell-KB-Artikel 000179687 führt GA10 als empfohlene Firmware für die 3-Gbit/s-SATA-Varianten dieser Platten, um vorzeitige Ausfälle zu verhindern.

Wenn Ihre Platten laufen und Sie kein Risiko eingehen wollen, ist es völlig in Ordnung, sie nicht anzufassen.

## Warnungen

- Dies ist **kein** offizielles Verfahren von Dell oder Seagate. Sie handeln auf eigenes Risiko. Ein fehlgeschlagener oder falscher Firmware-Download kann eine Platte dauerhaft unbrauchbar machen.
- Spielen Sie die `.fwh`-Datei **niemals** unverändert ein. Sie muss zuerst in `.lod` umgewandelt werden (Schritt 4). Im HDD-Guru-Forum wird eine Platte derselben Familie beschrieben, die genau dadurch zerstört wurde, dass die Datei mit Dell-Header gesendet wurde.
- Mischen Sie keine Firmware-Familien: nur `GA0x` → GA10. Kein `SN0x`, kein `GA6x`.
- Halten Sie ein aktuelles Backup bereit. Flashen Sie **eine Platte nach der anderen** und prüfen Sie sie, bevor Sie die nächste anfassen.
- Unterbrechen Sie den Download nicht, starten Sie nicht neu und trennen Sie nicht die Stromversorgung, solange `hdparm` läuft.
- Stellen Sie vor dem Flashen der Systemplatte sicher, dass Sie Out-of-Band-Zugriff haben (iLO, IPMI oder die Stromsteuerung im Panel des Providers).

## Schritt für Schritt

Alle Befehle werden als `root` ausgeführt.

### 0. Voraussetzungen

```bash
yum install -y hdparm smartmontools curl      # Debian/Ubuntu: apt install hdparm smartmontools curl
```

CentOS 7 wird nicht mehr unterstützt. Findet `yum` keinen Spiegelserver, stellen Sie es zuerst auf `vault.centos.org` um.

### 1. Platten identifizieren

```bash
lsblk -o NAME,SIZE,MODEL,REV,MOUNTPOINT
smartctl -i /dev/sda
```

Die wichtigen Zeilen der `smartctl`-Ausgabe:

```
Model Family:     Seagate Constellation ES.3
Device Model:     ST1000NM0033-9ZM173
Add. Product Id:  DELL(tm)
Firmware Version: GA06
SATA Version is:  SATA 3.0, 3.0 Gb/s (current: 3.0 Gb/s)
```

### 2. Dells Paket herunterladen und prüfen

Dell Driver ID **HPG73**, Version „GA10, A00“, veröffentlicht am 10. Mai 2016.

```bash
mkdir -p /root/ga10 && cd /root/ga10
curl -L -A "Mozilla/5.0" -O https://dl.dell.com/FOLDER03579122M/1/Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
sha256sum Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
```

Erwarteter SHA-256-Wert (laut Dells Download-Seite):

```
3d2efefa03b8942cdee4bca30012bed69badb611b79ebce20d7642601f698999
```

Weicht die Prüfsumme ab, hören Sie hier auf.

### 3. Paket entpacken, ohne es zu installieren

```bash
chmod +x Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
./Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN --extract ./extracted
ls -l extracted/payload/
```

Erwartet:

```
Successfully extracted to ./extracted
-rwxr-xr-t 1 root root 1691952 Feb 19  2016 GA10.fwh
```

### 4. `GA10.fwh` in `GA10.lod` umwandeln

`GA10.fwh` ist ein Seagate-LOD-Image, dem ein 304 Byte langer Dell-Header vorangestellt ist. Der Header muss weg.

**Mit dem Skript** (empfohlen: Es führt drei unabhängige Prüfungen durch und schreibt nichts, wenn eine davon fehlschlägt):

```bash
cd /root
git clone https://github.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial.git
cd Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial
./scripts/fwh2lod.sh -m ST1000NM0033-9ZM173 /root/ga10/extracted/payload/GA10.fwh /root/ga10/GA10.lod
```

Geben Sie nach `-m` Ihr eigenes Modell an. Ohne `git` laden Sie stattdessen nur die eine Datei:
`curl -LO https://raw.githubusercontent.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial/main/scripts/fwh2lod.sh && chmod +x fwh2lod.sh`

Erwartete Ausgabe (gekürzt):

```
Firmware revision : GA10
Model entries     : 5
   - ST4000NM0033-9ZM170
   - ST3000NM0033-9ZM178
   - ST2000NM0033-9ZM175
   - ST1000NM0033-9ZM173
   - ST500NM0003-9ZM172
Dell header       : 304 bytes (0x130)
LOD image         : 1691648 bytes
Check 1/3         : length is a multiple of 512            OK
Check 2/3         : LOD header checksum                    OK
Check 3/3         : stored length equals real length       OK
SHA-256           : 6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625
Known image       : yes - identical to the GA10 image tested in this guide
```

**Von Hand** (genau so wurde es auf dem Testserver gemacht):

```bash
cd /root/ga10
dd if=extracted/payload/GA10.fwh of=GA10.lod bs=304 skip=1
stat -c %s GA10.lod                      # muss 1691648 ausgeben
od -An -tu4 -j36 -N4 GA10.lod            # muss 1691648 ausgeben
od -An -v -tu2 -N64 GA10.lod | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s%65536}'   # muss 0 ausgeben
```

Weicht eine der drei Zahlen ab, machen Sie nicht weiter. Warum diese Prüfungen funktionieren, steht in [docs/fwh-header-format.md](docs/fwh-header-format.md) (auf Englisch).

**Prüfsumme vergleichen.** Beide Wege liefern dieselbe Datei, Byte für Byte. Dieses Image wurde auf dem Testserver eingespielt:

```bash
sha256sum /root/ga10/GA10.lod
```

```
6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625  /root/ga10/GA10.lod
```

Ein anderer Wert bedeutet, dass Ihre Datei nicht das Image ist, mit dem diese Anleitung getestet wurde. Spielen Sie sie nicht ein.

### 5. Eine Platte flashen, die nicht in Gebrauch ist

Beginnen Sie mit der unwichtigsten Platte (einer leeren oder einer Reserveplatte) und flashen Sie die übrigen danach einzeln.

```bash
DEV=/dev/sdb                                   # die Platte, die geflasht wird

lsblk -f $DEV                                  # prüfen, was darauf liegt
umount /mountpoint                             # alle eingehängten Partitionen dieser Platte aushängen
hdparm -I $DEV | grep -i microcode             # muss DOWNLOAD_MICROCODE auflisten

hdparm --fwdownload /root/ga10/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive $DEV
sleep 15

smartctl -i $DEV | grep -E 'Serial|Firmware'   # erwartet: Firmware Version: GA10
smartctl -H $DEV                               # erwartet: PASSED
```

Das gibt `hdparm` bei einem erfolgreichen Download aus:

```
/dev/sdb:
fwdownload: xfer_mode=3 min=1 max=1 size=512
............................................................ (viele Punkte) ... Done.
```

Hängen Sie danach die Dateisysteme wieder ein und prüfen Sie, ob die Daten lesbar sind.

Meldet `umount` `target is busy`, flashen Sie nicht. Suchen Sie zuerst den Prozess mit `fuser -vm /mountpoint`.

### 6. Die Systemplatte flashen (optional, erst lesen)

Die Systemplatte lässt sich nicht aushängen. Es gibt zwei Wege:

- **Im laufenden Betrieb**, während das Betriebssystem von der Platte läuft. So wurde es auf dem Testserver gemacht, und so arbeitet auch Dells eigenes Paket auf einem Dell-Rechner.
- **Aus einem Rescue-System**, wofür ein Neustart nötig ist. Bei einem Server mit sehr langer Uptime kann der Neustart das größere Risiko sein.

Vor dem Flashen im laufenden Betrieb: zuerst alle anderen Platten flashen und prüfen, ein frisches Backup anlegen und sicherstellen, dass Sie den Rechner Out-of-Band erreichen. Im schlimmsten Fall hängt die Platte beim Aktivieren der neuen Firmware, und der Server muss hart neu gestartet werden.

Das Image wird in den Arbeitsspeicher kopiert, und `nohup` lässt den Download weiterlaufen, falls die SSH-Sitzung abbricht:

```bash
cp /root/ga10/GA10.lod /dev/shm/ && cmp /root/ga10/GA10.lod /dev/shm/GA10.lod && echo OK
sync
nohup hdparm --fwdownload /dev/shm/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive /dev/sda > /dev/shm/sda-fw.log 2>&1 &
wait; tail -c 200 /dev/shm/sda-fw.log          # muss mit "Done." enden

smartctl -i /dev/sda | grep -E 'Serial|Firmware'
smartctl -H /dev/sda
touch /root/rw-test && rm -f /root/rw-test && echo "root file system is writable"
```

Starten Sie den Download nicht, wenn `cmp` kein `OK` ausgibt.

### 7. Abschließende Prüfungen

Ersetzen Sie `a b c d` durch die Buchstaben Ihrer eigenen Platten.

```bash
for d in a b c d; do smartctl -i /dev/sd$d | grep -E 'Serial|Firmware'; done
dmesg | grep -iE 'ata[0-9]+|I/O error' | tail

for d in a b c d; do smartctl -t short /dev/sd$d >/dev/null; done
sleep 150
for d in a b c d; do smartctl -l selftest /dev/sd$d | sed -n '6,7p'; done   # erwartet: Completed without error

rm -f /dev/shm/GA10.lod /dev/shm/sda-fw.log
```

Hinweise:

- Ein Neustart ist nicht nötig. `lsblk` und die Boot-Meldungen in `dmesg` zeigen bis zum nächsten Neustart weiter die alte Version, weil der Kernel sie zwischengespeichert hat. `smartctl -i` fragt die Platte direkt und zeigt die echte.
- Bewahren Sie `GA10.lod` auf. Wird eine Platte später gegen dasselbe Modell mit alter Firmware getauscht, brauchen Sie die Datei wieder.

## Fehlerbehebung

| Symptom | Bedeutung / was zu tun ist |
|---|---|
| Beim Ausführen der `.BIN` erscheint `Can't open IPMI device` | Auf Nicht-Dell-Hardware zu erwarten. `--extract` verwenden (Schritt 3). |
| `hdparm: command not found` | Installieren (Schritt 0). Auf die Platte wurde nichts geschrieben. |
| hdparm meldet `file size (...) not a multiple of 512` | Der Header wurde nicht korrekt entfernt. Schritt 4 wiederholen. |
| Keine Zeile `DOWNLOAD_MICROCODE` in `hdparm -I` | Die Platte ist für den Firmware-Download nicht erreichbar (RAID-Controller, USB-Bridge). Nicht weitermachen. |
| `umount: target is busy` | Etwas benutzt das Dateisystem. `fuser -vm /mountpoint`, Prozess beenden, dann aushängen. |
| hdparm meldet einen Fehler, oder die Version ist nach `Done.` noch die alte | Den Befehl **nicht** blind wiederholen. `dmesg` prüfen. Möglicherweise braucht die Platte ein vollständiges Aus- und Einschalten, um die Firmware zu aktivieren. |
| `fwh2lod.sh` bricht bei einer Prüfung ab | Die Datei hat einen Aufbau, den diese Anleitung nicht kennt. Nicht einspielen. |

## Wie die `.fwh`-Datei aufgebaut ist

Aufbau des Headers, Hex-Dump und die Begründung für die 304 Byte: [docs/fwh-header-format.md](docs/fwh-header-format.md) (auf Englisch).

## Quellen

- Dells Download-Seite für GA10, Driver ID HPG73: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=hpg73>
- Dell KB 000179687, vorzeitige Ausfälle bei Seagate-Megalodon/Makara-Platten: <https://www.dell.com/support/kbdoc/en-us/000179687/premature-failures-observed-on-seagate-megalodon-makara-sas-sata-drives-firmware-update-required-to-prevent-premature-failures>
- Dells Download-Seite für GA6E (6-Gbit/s-Variante), Driver ID 72RV5: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=72rv5>
- HDD-Guru-Forum, „Extract .LOD file (Seagate) from .FWH file (Dell)“: <https://forum.hddguru.com/viewtopic.php?f=13&t=45143>
- HDD-Guru-Forum, „Seagate SAS Firmware ST2000NM0023“ (Platte nach dem Flashen mit Dell-Header verloren): <https://forum.hddguru.com/viewtopic.php?f=13&t=39135>
- HDD-Guru-Forum, „ST2000NM0011 Firmware update over hdparm“: <https://forum.hddguru.com/viewtopic.php?t=38362>
- Blogbeitrag zur selben Methode für die ältere ST2000NM0011 (PA09): <https://hilfetisch.wordpress.com/2019/05/05/dell-seagate-constellation-st2000nm0011-st1000nm0011-st500nm0011-firmwareupgrade-pa08-pa09/>

## Mitmachen

Berichte sind willkommen, ob erfolgreich oder nicht. Bitte öffnen Sie ein Issue mit: Servermodell, SATA-Controller, Betriebssystem und Kernel, hdparm-Version, genauem Plattenmodell, Firmware vorher und nachher sowie der Angabe, ob die Platte eingehängt war.

## Lizenz und Haftungsausschluss

Text und Skripte stehen unter der [MIT-Lizenz](LICENSE). Die Firmware selbst gehört Dell und Seagate und ist nicht Teil dieses Repositorys.

Dieses Projekt steht in keiner Verbindung zu Dell, Seagate oder HP. Alles hier wird ohne jede Gewährleistung bereitgestellt. Für Ihre Hardware und Ihre Daten sind Sie selbst verantwortlich.
