#!/bin/bash

#set -x
#set -Eeuo pipefail

#_________________________________________________________________________________________________________________
#Блок переменных
common_dir="disaster-recovery"
replica_ip="192.168.1.120"
#_________________________________________________________________________________________________________________
clone_bcp() {
        #Переходим в директорию root'а и скачиваем с удаленного репозитория все бэкапы
        cd /root
        #True if file exists and is not empty and if file is a directory
        if [[ -d $common_dir && -s $common_dir ]]
        then
                echo 'Бэкап уже скачан'
        else
                git init
                # Скачиваем ключ хоста, чтобы ключ уже был известен и не нужно было вводить yes при первом подключении к репозиторию
                ssh-keyscan github.com >> ~/.ssh/known_hosts

                git clone git@github.com:Vladislav-cmd/disaster-recovery.git
        fi
}
#_________________________________________________________________________________________________________________
web_restore() {
        #Удаляем текущую конфигурацию nginx & apache2 & html файлы
        rm -rf /etc/nginx
        rm -rf /etc/apache2
        rm -rf /var/www/*

        cd /root/disaster-recovery
        #Копируем готовые файлы в целевые директории
        cp -r nginx apache2 /etc/
        cp -r /root/disaster-recovery/web/{html,html1,html2} /var/www/
        #Выполняем рестарт сервисом для включения новой конфигурации
        service nginx restart
        service apache2 restart
}
#_________________________________________________________________________________________________________________
mysql_restore() {
        #Удаляем текущую конфигурацию mysqld.cnf
        rm /etc/mysql/mysql.conf.d/mysqld.cnf

        #Копируем конфигурационный файл
        cp /root/disaster-recovery/mysql/mysql_cfg_bcp/master_node/mysqld.cnf /etc/mysql/mysql.conf.d/
        service mysql restart

        mysql -e "CREATE USER repl@'%' IDENTIFIED WITH 'caching_sha2_password' BY 'repltest';"
        mysql -e "GRANT REPLICATION SLAVE ON *.* TO repl@'%';"

        #Восстанавливаем БД
        cd /root/disaster-recovery/mysql/mysql_db_backup/
        #Получаем список из БД, предварительно отпарсив только название
                #-exec ... {} \; — выполняет указанную команду для каждого найденного файла.
                #basename — утилита, которая отсекает весь путь, оставляя только имя файла.
                #-s .sql — суффикс (расширение), который basename автоматически удалит с конца имени.
        db_list=$(find /root/disaster-recovery/mysql/mysql_db_backup/ -name "*.sql" -exec basename -s .sql {} \;)

        for db in $db_list
        do
                #Создаем каждую БД перед заливкой
                mysql -e "create database $db;"
                #Заливаем файл.sql в созданную БД
                mysql -u root $db < $db.sql
        done

        #Восстановление для реплики - надо подключаться по ssh (уже зараннее настроена авторизация по ключу для root'a)
        #-o StrictHostKeyChecking=no   - чтобы при первом подключении не нужно было вводить yes
        ssh -o StrictHostKeyChecking=no root@$replica_ip << 'EOF'
                cd /root
                git init
                # Скачиваем ключ хоста, чтобы ключ уже был известен и не нужно было вводить yes при первом подключении к репозиторию
                ssh-keyscan github.com >> ~/.ssh/known_hosts
                git clone git@github.com:Vladislav-cmd/disaster-recovery.git

                rm /etc/mysql/mysql.conf.d/mysqld.cnf
                cp /root/disaster-recovery/mysql/mysql_cfg_bcp/replica_node/mysqld.cnf /etc/mysql/mysql.conf.d/
                service mysql restart

                #Копируем файлы табличных бэкапов и crontab
                cp -r /root/disaster-recovery/scripts/{crontab,tables_bcp.sh} /root
                #Заменяем на наш crontab файл с запуском скрипта потабличного бекапа баз раз в сутки в 3 ночи
                cp /root/crontab /etc/crontab
                rm -rf /root/disaster-recovery

                #Теперь включаем репликацию.
                mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.1.110', SOURCE_USER='repl', SOURCE_PASSWORD='repltest', SOURCE_AUTO_POSITION = 1, GET_SOURCE_PUBLIC_KEY = 1;"
                mysql -e "STOP REPLICA;"
                mysql -e "START REPLICA;"

EOF
}
#_________________________________________________________________________________________________________________
monitoring_restore() {
        cd /root
        /bin/systemctl daemon-reload
        /bin/systemctl enable grafana-server
        /bin/systemctl start grafana-server

        rm /root/grafana_13.2.1_33191028959_linux_amd64.deb
}
#_________________________________________________________________________________________________________________
elk_restore() {
        cd /root
        #Установка №1 Elasticsearch
        cp /root/disaster-recovery/elk/elasticsearch_cfg/jvm.options /etc/elasticsearch/jvm.options.d/
        cp /root/disaster-recovery/elk/elasticsearch_cfg/elasticsearch.yml /etc/elasticsearch/
        systemctl daemon-reload
        systemctl enable --now elasticsearch.service

        #Установка №2 Kibana
        systemctl daemon-reload
        systemctl enable --now kibana.service
        cp /root/disaster-recovery/elk/kibana_cfg/kibana.yml /etc/kibana/
        systemctl restart kibana

        #Установка №3 Logstash
        systemctl enable --now logstash.service
        cp /root/disaster-recovery/elk/logstash_cfg/logstash.yml /etc/logstash/
        cp /root/disaster-recovery/elk/logstash_cfg/logstash-nginx-es.conf /etc/logstash/conf.d/
        systemctl restart logstash.service

        #Установка №4 Filebeat
        #dpkg -i filebeat_8.17.1_amd64.deb
        cp /root/disaster-recovery/elk/filebeat_cfg/filebeat.yml /etc/filebeat/
        systemctl restart filebeat
}
#_________________________________________________________________________________________________________________
#Реализация Here-doc (help) для скрипта: (basename - печатает последний компонент в пути к файлу, то есть имя файла)
show_help() {
        cat << EOF

Использование скрипта: $(basename "$0")

Описание:
   Этот скрипт выполняет бэкап потаблично из каждой БД на сервере в соответствующую директорию.

   Краткая информация по алгоритму работы:
        1. Получаем списоб БД на сервере через переменную db_list. Если нужно бэкапить только конкретные, то прописываем руками список.
        2. Подготавливаем директорию под бэкапы.
        3. Через цикл for перебираем каждую БД из списка db_list, получаем список таблиц table_list в БД, создаем подпапку для соответствующей БД.
        4. Перебираем через цикл for список таблиц в БД и сохраняем каждую таблицу в соответствующую директорию с названием самой таблицы.

EOF
}
#_________________________________________________________________________________________________________________
#Если 1-ый параметр не ввели, то запускается функция скрипта, если не пустой и там есть значение для справки, то выводит Here-doc
if [ -z $1 ]
then
        #_________________________________________________________________________________________________________________
        # 1) Функция, которая скачивает с git репозитория все бэкапы в директорию disaster-recovery
        clone_bcp
        # 2) #Функция восстановления конфигурации nginx & apache2
        web_restore
        # 3) #Функция восстановления Master-Slave MySQL, восстановления БД'ых и запуска потабличного бэкапа с реплики через crontab
        mysql_restore
        # 4) #Функция восстановления мониторинга, Prometheus и node_exporter + Grafana (дополнительная настройка через WEB)
        monitoring_restore
        # 5) #Функция восстановления стека логирования ELK (дополнительная настройка через WEB)
        elk_restore
        #_________________________________________________________________________________________________________________
else
        #Если первым параметром был введен help или h, то выводим информацию по скрипту.
        if [[ $1 = "-help" || $1 = "help" || $1 = "-h" || $1 = "h" ]]
        then
                show_help
        else
                echo "Для отображение справки по скрипту введите '$0 -help' или '$0 help' или '$0 -h' или '$0 h'"
                exit 2
        fi
fi
#_________________________________________________________________________________________________________________
