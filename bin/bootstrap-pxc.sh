#!/bin/bash

set -e
set +H

[ "$DEBUG" == "1" ] && set -x && set +e

# Bootstrap the cluster
echo "=> Bootstrapping PXC cluster into ${PXC_VOLUME}..."
#[ "$(ls -A ${PXC_VOLUME})" ] && echo "==> Data files already exist! attempting to use these..." || mysqld --initialize --user=mysql --datadir=${PXC_VOLUME} >/dev/null 2>&1
[ "$(ls -A ${PXC_VOLUME})" ] && echo "==> Data files already exist! attempting to use these..." || mysqld --initialize --user=mysql --datadir=${PXC_VOLUME}

echo "=> Initializing SQL for PXC cluster"
echo "CREATE USER 'root'@'%' IDENTIFIED BY '${PXC_ROOT_PASSWORD}';" > /tmp/init.sql
echo "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;" >> /tmp/init.sql

echo "CREATE USER 'sstuser'@'%' IDENTIFIED BY '${PXC_SST_PASSWORD}';" >> /tmp/init.sql
echo "GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO 'sstuser'@'%';" >> /tmp/init.sql

#echo "UPDATE mysql.user set Password=PASSWORD('${PXC_ROOT_PASSWORD}') where user='root';" >> /tmp/init.sql
#echo "DELETE FROM mysql.user WHERE User='';" >> /tmp/init.sql

echo "DROP DATABASE test;" >> /tmp/init.sql
echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> /tmp/init.sql

echo "FLUSH PRIVILEGES;" >> /tmp/init.sql

touch ${PXC_CONF_FLAG}
touch ${PXC_BOOTSTRAP_FLAG}

# Import an init SQL
if [ "${PXC_INIT_SQL}" != "**ChangeMe**" -a ! -z "${PXC_INIT_SQL}" ]; then
   # Save the SQL temporary
   wget -O /tmp/init_exteranl.sql "${PXC_INIT_SQL}" 
   if [ $? -eq 0 ]; then
      echo "=> I'm importing this SQL file when bootstraping: ${PXC_INIT_SQL}"
      cat /tmp/init_exteranl.sql >> /tmp/init.sql
   fi
fi   

echo "=> Starting supervisord (with bootstrap)"
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord_bootstrap.conf
