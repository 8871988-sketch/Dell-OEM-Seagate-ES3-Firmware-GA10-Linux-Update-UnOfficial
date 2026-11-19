# Диски Seagate Constellation ES.3 з OEM-прошивкою Dell (ST1000NM0033 та споріднені): оновлення до GA10 на Linux-сервері не від Dell

**Неофіційний посібник спільноти.** Прошивка тут не розповсюджується: оригінальний пакет ви завантажуєте з сайту Dell самі.

Мови: [English](README.md) | **Українська**

---

## Про що це

Диски Seagate Constellation ES.3 SATA з маркуванням Dell (`Add. Product Id: DELL(tm)`, прошивка `GA0x`) часто опиняються в серверах інших виробників: в орендованих dedicated-серверах, у відновленому залізі, в домашніх лабораторіях. Dell випустила для них новішу прошивку **GA10**, але:

- пакет оновлення Dell відмовляється працювати на залізі не від Dell (`Can't open IPMI device`, «not compatible with your system configuration»);
- прошивка самої Seagate (`SN0x`) призначена для роздрібних дисків, і ставити її на OEM-диски Dell не можна.

Посібник показує, як дістати образ прошивки з пакета Dell, зрізати службовий заголовок Dell, перевірити результат і залити його звичайним `hdparm`. Кожну команду нижче виконано на реальному сервері.

## Перевірена конфігурація

| Параметр | Значення |
|---|---|
| Сервер | HP ProLiant DL120 G7, вбудований SATA-контролер (диски видно як звичайні `/dev/sdX`) |
| ОС | CentOS 7, ядро 3.10.0-1062 (x86_64), Plesk |
| Інструменти | hdparm 9.43, smartmontools 7.0 |
| Диски | 4 × Seagate `ST1000NM0033-9ZM173`, Dell OEM |
| Прошивка до | `GA06` (2 диски), `GA0A` (2 диски) |
| Прошивка після | `GA10` (усі 4 диски) |
| Дата | 19.11.2026 |

Результат: усі чотири диски прийняли образ з першої спроби. Нова версія стала активною одразу, без перезавантаження і без вимкнення живлення. Три диски шилися відмонтованими, системний диск (boot і root) шився на ходу, під час роботи ОС із нього. Після цього SMART показав `PASSED`, а короткі самотести на всіх чотирьох завершилися без помилок.

## Чи підходить посібник для вашого диска

Виконайте `smartctl -i /dev/sdX` (або `scripts/list-drives.sh`). Посібник підходить, лише якщо виконується **все** з цього:

1. `Device Model` є одним із
   `ST4000NM0033-9ZM170`, `ST3000NM0033-9ZM178`, `ST2000NM0033-9ZM175`, `ST1000NM0033-9ZM173`, `ST500NM0003-9ZM172`
2. `Add. Product Id` дорівнює `DELL(tm)`
3. `Firmware Version` починається з `GA0` (наприклад `GA06`, `GA0A`, `GA0D`, `GA0F`)
4. Диск під'єднано напряму до порту SATA/AHCI, тобто `hdparm` має до нього доступ

Реально перевірено лише `ST1000NM0033-9ZM173`. Решта чотири моделі перелічені в заголовку того самого файлу прошивки і на сторінці завантаження Dell, але їх тут ніхто не шив.

Посібник **не** підходить для:

| Диск | Що робити натомість |
|---|---|
| Диски Dell із прошивкою `GA6x` (варіант 6 Гбіт/с) | Для них Dell вказує `GA6E`, це інший пакет (Driver ID `72RV5`). GA10 на них не заливати. |
| Роздрібні диски з прошивкою `SN0x` | Брати прошивку на сайті Seagate. |
| Моделі SAS (`ST…NM0023`, прошивка `GSxx`) | Інша прошивка й інші інструменти. |
| Диски за апаратним RAID-контролером (PERC, Smart Array, MegaRAID) | Не перевірялося. `hdparm` зазвичай до таких дисків не дістає. |

## Навіщо взагалі оновлювати

- В описі GA10 Dell згадує виправлення неточного підрахунку помилок позиціювання в SMART, через який SMART міг несподівано спрацювати, а також загальне підвищення надійності.
- У статті Dell KB 000179687 GA10 названо рекомендованою прошивкою для варіантів 3 Гбіт/с цих дисків, щоб запобігти передчасним відмовам.

Якщо диски працюють і ризикувати не хочеться, не чіпати їх теж цілком нормальний вибір.

## Попередження

- Це **не** офіційна процедура Dell чи Seagate. Ви дієте на власний ризик. Невдала або неправильна заливка може зробити диск непридатним назавжди.
- **Ніколи** не заливайте файл `.fwh` як є. Спершу його треба перетворити на `.lod` (крок 4). На форумі HDD Guru описано диск цієї ж родини, який загинув саме через заливку файлу разом із заголовком Dell.
- Не змішуйте родини прошивок: лише `GA0x` → GA10. Жодних `SN0x` чи `GA6x`.
- Майте свіжий бекап. Шийте **по одному диску** і перевіряйте його, перш ніж братися за наступний.
- Не переривайте заливку, не перезавантажуйте сервер і не вимикайте живлення, поки працює `hdparm`.
- Перед прошивкою системного диска переконайтеся, що маєте позасмуговий доступ (iLO, IPMI або керування живленням у панелі провайдера).

## Покроково

Усі команди виконуються від `root`.

### 0. Підготовка

```bash
yum install -y hdparm smartmontools curl      # Debian/Ubuntu: apt install hdparm smartmontools curl
```

CentOS 7 знято з підтримки. Якщо `yum` не знаходить дзеркало, спершу перемкніть його на `vault.centos.org`.

### 1. Визначити диски

```bash
lsblk -o NAME,SIZE,MODEL,REV,MOUNTPOINT
smartctl -i /dev/sda
```

Важливі рядки у виводі `smartctl`:

```
Model Family:     Seagate Constellation ES.3
Device Model:     ST1000NM0033-9ZM173
Add. Product Id:  DELL(tm)
Firmware Version: GA06
SATA Version is:  SATA 3.0, 3.0 Gb/s (current: 3.0 Gb/s)
```

### 2. Завантажити пакет Dell і перевірити його

Dell Driver ID **HPG73**, версія «GA10, A00», випущено 10 травня 2016 року.

```bash
mkdir -p /root/ga10 && cd /root/ga10
curl -L -A "Mozilla/5.0" -O https://dl.dell.com/FOLDER03579122M/1/Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
sha256sum Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
```

Очікуваний SHA-256 (зі сторінки завантаження Dell):

```
3d2efefa03b8942cdee4bca30012bed69badb611b79ebce20d7642601f698999
```

Якщо контрольна сума інша, далі не йдіть.

### 3. Розпакувати пакет без встановлення

```bash
chmod +x Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
./Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN --extract ./extracted
ls -l extracted/payload/
```

Очікувано:

```
Successfully extracted to ./extracted
-rwxr-xr-t 1 root root 1691952 Feb 19  2016 GA10.fwh
```

### 4. Перетворити `GA10.fwh` на `GA10.lod`

`GA10.fwh` складається з образу Seagate LOD, перед яким стоїть заголовок Dell довжиною 304 байти. Заголовок треба прибрати.

**Скриптом** (рекомендовано: він робить три незалежні перевірки і нічого не записує, якщо хоч одна не пройшла):

```bash
cd /root
git clone https://github.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial.git
cd Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial
./scripts/fwh2lod.sh -m ST1000NM0033-9ZM173 /root/ga10/extracted/payload/GA10.fwh /root/ga10/GA10.lod
```

Після `-m` вкажіть свою модель. Якщо `git` немає, завантажте лише один файл:
`curl -LO https://raw.githubusercontent.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial/main/scripts/fwh2lod.sh && chmod +x fwh2lod.sh`

Очікуваний вивід (скорочено):

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

**Вручну** (саме так було зроблено на тестовому сервері):

```bash
cd /root/ga10
dd if=extracted/payload/GA10.fwh of=GA10.lod bs=304 skip=1
stat -c %s GA10.lod                      # має вивести 1691648
od -An -tu4 -j36 -N4 GA10.lod            # має вивести 1691648
od -An -v -tu2 -N64 GA10.lod | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s%65536}'   # має вивести 0
```

Якщо хоч одне з трьох чисел інше, не продовжуйте. Чому ці перевірки працюють, пояснено в [docs/fwh-header-format.md](docs/fwh-header-format.md) (англійською).

**Порівняйте контрольну суму.** Обидва способи дають однаковий файл, байт у байт. Саме цей образ було залито на тестовому сервері:

```bash
sha256sum /root/ga10/GA10.lod
```

```
6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625  /root/ga10/GA10.lod
```

Інше значення означає, що ваш файл не є образом, на якому перевірено цей посібник. Не заливайте його.

### 5. Прошити диск, який не використовується

Почніть із найменш важливого диска (порожнього або запасного), далі шийте решту по одному.

```bash
DEV=/dev/sdb                                   # диск, який шиємо

lsblk -f $DEV                                  # що на ньому є
umount /mountpoint                             # відмонтувати всі змонтовані розділи цього диска
hdparm -I $DEV | grep -i microcode             # має бути рядок DOWNLOAD_MICROCODE

hdparm --fwdownload /root/ga10/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive $DEV
sleep 15

smartctl -i $DEV | grep -E 'Serial|Firmware'   # очікуємо: Firmware Version: GA10
smartctl -H $DEV                               # очікуємо: PASSED
```

Що друкує `hdparm` під час успішної заливки:

```
/dev/sdb:
fwdownload: xfer_mode=3 min=1 max=1 size=512
............................................................ (багато крапок) ... Done.
```

Після цього змонтуйте файлові системи назад і перевірте, що дані читаються.

Якщо `umount` відповідає `target is busy`, не шийте. Спершу знайдіть процес командою `fuser -vm /mountpoint`.

### 6. Прошити системний диск (необов'язково, спершу прочитайте)

Системний диск відмонтувати не можна. Є два шляхи:

- **На ходу**, поки ОС працює з цього диска. Так було зроблено на тестовому сервері, і так само працює власний пакет Dell на машинах Dell.
- **З rescue-системи**, для чого потрібне перезавантаження. На сервері з дуже довгим аптаймом саме перезавантаження може бути більшим ризиком.

Перед прошивкою на ходу: спершу прошийте й перевірте всі інші диски, зробіть свіжий бекап і переконайтеся, що маєте позасмуговий доступ до машини. Найгірший сценарій: диск зависне під час активації нової прошивки, і сервер доведеться перезавантажити примусово.

Образ копіюється в оперативну пам'ять, а `nohup` не дає заливці перерватися, якщо обірветься SSH:

```bash
cp /root/ga10/GA10.lod /dev/shm/ && cmp /root/ga10/GA10.lod /dev/shm/GA10.lod && echo OK
sync
nohup hdparm --fwdownload /dev/shm/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive /dev/sda > /dev/shm/sda-fw.log 2>&1 &
wait; tail -c 200 /dev/shm/sda-fw.log          # має закінчуватися на "Done."

smartctl -i /dev/sda | grep -E 'Serial|Firmware'
smartctl -H /dev/sda
touch /root/rw-test && rm -f /root/rw-test && echo "root file system is writable"
```

Не запускайте заливку, якщо `cmp` не вивів `OK`.

### 7. Остаточні перевірки

Підставте літери своїх дисків замість `a b c d`.

```bash
for d in a b c d; do smartctl -i /dev/sd$d | grep -E 'Serial|Firmware'; done
dmesg | grep -iE 'ata[0-9]+|I/O error' | tail

for d in a b c d; do smartctl -t short /dev/sd$d >/dev/null; done
sleep 150
for d in a b c d; do smartctl -l selftest /dev/sd$d | sed -n '6,7p'; done   # очікуємо: Completed without error

rm -f /dev/shm/GA10.lod /dev/shm/sda-fw.log
```

Примітки:

- Перезавантаження не потрібне. `lsblk` і завантажувальні повідомлення в `dmesg` показуватимуть стару версію до наступного перезавантаження, бо ядро її закешувало. `smartctl -i` питає диск напряму і показує справжню.
- Збережіть `GA10.lod`. Якщо диск колись замінять на таку саму модель зі старою прошивкою, файл знадобиться знову.

## Усунення проблем

| Симптом | Що це означає і що робити |
|---|---|
| Запуск `.BIN` друкує `Can't open IPMI device` | Очікувано на залізі не від Dell. Використайте `--extract` (крок 3). |
| `hdparm: command not found` | Встановіть його (крок 0). На диск нічого не записалося. |
| hdparm пише `file size (...) not a multiple of 512` | Заголовок зрізано неправильно. Повторіть крок 4. |
| У `hdparm -I` немає рядка `DOWNLOAD_MICROCODE` | Диск недоступний для заливки прошивки (RAID-контролер, USB-міст). Не продовжуйте. |
| `umount: target is busy` | Файлову систему щось використовує. `fuser -vm /mountpoint`, зупиніть процес, потім відмонтуйте. |
| hdparm повідомив про помилку, або після `Done.` версія лишилася старою | **Не** повторюйте команду наосліп. Перегляньте `dmesg`. Можливо, диску для активації прошивки потрібне повне вимкнення живлення. |
| `fwh2lod.sh` зупинився на перевірці | Файл має структуру, якої цей посібник не знає. Не заливайте його. |

## Як побудований файл `.fwh`

Структура заголовка, hex-дамп і пояснення, звідки взялися 304 байти: [docs/fwh-header-format.md](docs/fwh-header-format.md) (англійською).

## Джерела

- Сторінка завантаження GA10 на сайті Dell, Driver ID HPG73: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=hpg73>
- Dell KB 000179687, передчасні відмови дисків Seagate Megalodon/Makara: <https://www.dell.com/support/kbdoc/en-us/000179687/premature-failures-observed-on-seagate-megalodon-makara-sas-sata-drives-firmware-update-required-to-prevent-premature-failures>
- Сторінка завантаження GA6E (варіант 6 Гбіт/с), Driver ID 72RV5: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=72rv5>
- Форум HDD Guru, «Extract .LOD file (Seagate) from .FWH file (Dell)»: <https://forum.hddguru.com/viewtopic.php?f=13&t=45143>
- Форум HDD Guru, «Seagate SAS Firmware ST2000NM0023» (диск втрачено після заливки із заголовком Dell): <https://forum.hddguru.com/viewtopic.php?f=13&t=39135>
- Форум HDD Guru, «ST2000NM0011 Firmware update over hdparm»: <https://forum.hddguru.com/viewtopic.php?t=38362>
- Стаття в блозі про той самий метод для старішого ST2000NM0011 (PA09), німецькою: <https://hilfetisch.wordpress.com/2019/05/05/dell-seagate-constellation-st2000nm0011-st1000nm0011-st500nm0011-firmwareupgrade-pa08-pa09/>

## Як допомогти

Звіти вітаються, і про успіх, і про невдачу. Відкрийте issue і вкажіть: модель сервера, SATA-контролер, ОС і ядро, версію hdparm, точну модель диска, прошивку до і після, а також чи був диск змонтований.

## Ліцензія і відмова від відповідальності

Текст і скрипти поширюються за [ліцензією MIT](LICENSE). Сама прошивка належить Dell і Seagate і не входить до цього репозиторію.

Проєкт не пов'язаний із Dell, Seagate чи HP. Усе надається без жодних гарантій. За своє залізо й дані відповідаєте ви самі.
