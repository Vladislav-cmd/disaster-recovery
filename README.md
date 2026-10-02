# Disaster Recovery

## Описание

Этот скрипт выполняет восстановление сервисов, включая ноду репликации MySQL.

---

## Инициация запуска

### Вариант 1. Клонирование репозитория

Из-под `root` перейти в директорию `/root` и выполнить:

```bash
cd /root

git init
git clone git@github.com:Vladislav-cmd/disaster-recovery.git
```

Запустить скрипт:

```bash
bash /root/disaster-recovery/scripts/dr_script.sh
```

### Вариант 2. Ручное создание скрипта

Можно скопировать содержимое `dr_script.sh` и вставить его в созданный на сервере файл:

```bash
cd /root
cat > dr_script.sh
```

После вставки содержимого завершить ввод сочетанием:

```text
Ctrl+D
```

Запуск скрипта:

```bash
bash dr_script.sh
```

### Вызов справки

```bash
bash dr_script.sh -h
```

---

# Установка необходимых пакетов

Перед установкой перейти под пользователя `root`:

```bash
sudo su
cd /root
```

## 1. Обновление репозиториев

```bash
apt update
```

## 2. Базовые утилиты

```bash
apt install -y net-tools whois traceroute nmap unzip {jnet,h,io,if,a}top iptraf-ng nmon
```

## 3. Пакет для iptables

```bash
apt install -y iptables-persistent
```

## 4. Пакеты для сервисов Nginx, Apache и MySQL

```bash
apt install -y nginx apache2 mysql-server-8.0
```

## 5. Пакеты для мониторинга Prometheus и Grafana

Установить Prometheus и Nginx Exporter:

```bash
apt install -y prometheus prometheus-nginx-exporter
```

Установить зависимости Grafana:

```bash
apt-get install -y adduser libfontconfig1 musl
```

Скачать пакет Grafana:

```bash
wget https://dl.grafana.com/grafana/release/13.2.1/grafana_13.2.1_33191028959_linux_amd64.deb
```

Установить Grafana:

```bash
dpkg -i grafana_13.2.1_33191028959_linux_amd64.deb
```

## 6. Пакеты ELK Stack

С удалённого сервера необходимо скачать пакеты в директорию `/root`.

> **Важно:** Elasticsearch, Kibana, Logstash и Filebeat должны быть одной версии — `8.17.1`.

Установить Java:

```bash
apt install default-jdk -y
```

Установить Elasticsearch:

```bash
dpkg -i elasticsearch_8.17.1-amd64.deb
```

Установить Kibana:

```bash
dpkg -i kibana_8.17.1_amd64.deb
```

Установить Logstash:

```bash
dpkg -i logstash_8.17.1_amd64.deb
```

Установить Filebeat:

```bash
dpkg -i filebeat_8.17.1_amd64.deb
```

---

# Структура файлов репозитория

```text
disaster-recovery/
│
├── apache2/
│   └── Конфигурация Apache
│
├── elk/
│   ├── elasticsearch_cfg/
│   ├── filebeat_cfg/
│   ├── kibana_cfg/
│   └── logstash_cfg/
│
├── mysql/
│   ├── mysql_cfg_bcp/
│   │   └── Конфигурации MySQL Master-Slave
│   │
│   └── mysql_db_bcp/
│       └── Бэкапы баз данных
│
├── nginx/
│   └── Конфигурация Nginx
│
├── scripts/
│   ├── crontab
│   ├── dr_script.sh
│   └── tables_bcp.sh
│
├── DR services scheme.drawio
└── DR services scheme.png
```

### Описание основных файлов

- `apache2/` — директория с конфигурацией Apache.
- `elk/` — директория с конфигурациями ELK Stack:
  - `elasticsearch_cfg/`
  - `filebeat_cfg/`
  - `kibana_cfg/`
  - `logstash_cfg/`
- `mysql/` — директория для восстановления MySQL:
  - `mysql_cfg_bcp/` — конфигурации MySQL Master-Slave;
  - `mysql_db_bcp/` — резервные копии баз данных.
- `nginx/` — директория с конфигурацией Nginx.
- `scripts/` — директория со скриптами и файлами `crontab`:
  - `crontab` — файл для запуска `tables_bcp.sh` на реплике MySQL;
  - `dr_script.sh` — основной Disaster Recovery скрипт для восстановления сервисов;
  - `tables_bcp.sh` — скрипт потабличного резервного копирования БД на реплике MySQL.
- `DR services scheme.drawio` — схема настроенных сервисов в формате Draw.io.
- `DR services scheme.png` — схема настроенных сервисов в формате PNG.

---

# Алгоритм работы

## 1. Клонирование конфигурации — `clone_bcp`

Вызывается функция:

```text
clone_bcp
```

Функция клонирует Git-репозиторий, содержащий необходимые конфигурационные файлы для восстановления сервисов.

---

## 2. Восстановление WEB-сервера — `web_restore`

Вызывается функция:

```text
web_restore
```

Функция восстанавливает конфигурацию WEB-сервера с балансировкой нагрузки:

```text
Nginx Frontend
      ↓
Apache Backend
```

WEB-сервер доступен по адресу:

```text
http://192.168.1.110
```

---

## 3. Восстановление MySQL — `mysql_restore`

Вызывается функция:

```text
mysql_restore
```

Функция восстанавливает:

- конфигурацию MySQL Master-Slave;
- репликацию данных;
- скрипты резервного копирования.

Скрипт подключается по SSH к ноде реплики и копирует:

```text
tables_bcp.sh
```

в директорию:

```text
/root
```

Также заменяется стандартный файл `crontab` для ежедневного запуска:

```bash
tables_bcp.sh
```

---

## 4. Восстановление мониторинга — `monitoring_restore`

Вызывается функция:

```text
monitoring_restore
```

Функция запускает Grafana.

Prometheus уже установлен, поэтому его необходимо добавить в качестве источника данных в Grafana.

### Grafana

WEB-интерфейс:

```text
http://192.168.1.110:3000
```

Данные для входа по умолчанию:

```text
Login:    admin
Password: admin
```

### Prometheus

WEB-интерфейс:

```text
http://192.168.1.110:9090
```

### Добавление Prometheus в Grafana

Перейти:

```text
Connections
└── Data sources
    └── Add data source
        └── Prometheus
```

В поле **Connection** указать:

```text
http://localhost:9090
```

После этого нажать:

```text
Save & test
```

### Импорт Dashboard

Перейти:

```text
Dashboards
└── New
    └── Import dashboard
```

Ввести ID:

```text
1860
```

Затем:

```text
Load → Import
```

---

## 5. Восстановление ELK Stack — `elk_restore`

Вызывается функция:

```text
elk_restore
```

Функция последовательно восстанавливает конфигурации:

1. Elasticsearch
2. Kibana
3. Logstash
4. Filebeat

### Kibana

WEB-интерфейс:

```text
http://192.168.1.110:5601
```

Для просмотра индексов перейти:

```text
Management
└── Stack Management
    └── Data
        └── Index Management
```

Здесь будет отображаться текущий индекс `weblogs` с логами.

### Генерация дополнительных логов

Для создания дополнительных записей в `weblogs` можно выполнить:

```bash
curl http://localhost/example
```

### Создание Data View

В Kibana перейти:

```text
Dashboards
└── Create data view
```

Указать:

```text
Name: Nginx
Index pattern: weblogs*
```

После этого нажать:

```text
Save data view to Kibana
```

### Создание Dashboard

Перейти:

```text
Create a Dashboard
└── Create Visualization
```

Например, для горизонтальной оси можно использовать:

```text
url.original.keyword
```

или:

```text
http.response.status.code
```

Для вертикальной оси:

```text
count
```

После настройки:

```text
Save and Return → Save
```

---

## 6. Автозагрузка сервисов

Все восстановленные сервисы добавляются в автозагрузку.

Проверить состояние автозагрузки Nginx:

```bash
systemctl list-unit-files --type=service --state=enabled | grep nginx
```

Apache:

```bash
systemctl list-unit-files --type=service --state=enabled | grep apache
```

MySQL:

```bash
systemctl list-unit-files --type=service --state=enabled | grep mysql
```

Kibana:

```bash
systemctl list-unit-files --type=service --state=enabled | grep kibana
```

Prometheus:

```bash
systemctl list-unit-files --type=service --state=enabled | grep prometheus
```

---

# Доступ к сервисам

| Сервис | Адрес | Назначение |
|---|---|---|
| WEB | `http://192.168.1.110` | Nginx + Apache |
| Grafana | `http://192.168.1.110:3000` | Мониторинг и визуализация |
| Prometheus | `http://192.168.1.110:9090` | Сбор и хранение метрик |
| Kibana | `http://192.168.1.110:5601` | Просмотр и анализ логов |

---

## Основные функции скрипта

| Функция | Назначение |
|---|---|
| `clone_bcp` | Клонирование конфигурационных файлов из Git |
| `web_restore` | Восстановление Nginx и Apache |
| `mysql_restore` | Восстановление MySQL Master-Slave и репликации |
| `monitoring_restore` | Восстановление системы мониторинга |
| `elk_restore` | Восстановление ELK Stack |
