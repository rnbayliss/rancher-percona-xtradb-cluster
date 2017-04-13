FROM ubuntu:16.04

MAINTAINER Rich Bayliss <richbayliss@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive

# install Percona XtraDB Cluster 5.7
RUN echo "deb http://repo.percona.com/apt xenial main" > /etc/apt/sources.list.d/percona.list
RUN echo "deb-src http://repo.percona.com/apt xenial main" >> /etc/apt/sources.list.d/percona.list

RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8507EFA5
RUN apt-get update && \
    apt-get -y install percona-xtradb-cluster-57 pwgen supervisor openssh-server sshpass xinetd dnsutils wget

RUN service mysql stop
	
# configure some ENV variables
ENV PXC_SST_PASSWORD **ChangeMe**
ENV PXC_ROOT_PASSWORD **ChangeMe**
ENV PXC_INIT_SQL **ChangeMe**
ENV SERVICE_NAME pxc
ENV SERVICE_NODE_COUNT 3
ENV NODE_COUNT_FIRST_RETRY_SECONDS 10
ENV NODE_COUNT_SECOND_RETRY_SECONDS 180

ENV PXC_VOLUME /var/lib/mysql
ENV PXC_CONF /etc/mysql/conf.d/pxc.cnf
ENV PXC_CONF_FLAG /etc/mysql/pxc.configured
ENV PXC_BOOTSTRAP_FLAG /etc/mysql/pxc.bootstrapped
ENV SSH_USER root
ENV SSH_PORT 2222
ENV MYSQLCHK_PORT 9200
ENV SSH_OPTS -p ${SSH_PORT} -o ConnectTimeout=20 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

ENV DEBUG 0

RUN mkdir -p /var/log/supervisor /var/run/sshd
RUN perl -p -i -e "s/^Port .*/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
RUN perl -p -i -e "s/#?PasswordAuthentication .*/PasswordAuthentication yes/g" /etc/ssh/sshd_config
RUN perl -p -i -e "s/#?PermitRootLogin .*/PermitRootLogin yes/g" /etc/ssh/sshd_config
RUN grep ClientAliveInterval /etc/ssh/sshd_config >/dev/null 2>&1 || echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config

VOLUME ["${PXC_VOLUME}"]

RUN mkdir -p /usr/local/bin
RUN echo "mysqlchk ${MYSQLCHK_PORT}/tcp #mysqlchk" >> /etc/services
ADD ./bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh
ADD ./etc/mysql/conf.d/pxc.cnf /etc/mysql/conf.d/pxc.cnf
RUN chown mysql:mysql /etc/mysql/conf.d/*
RUN chmod 600 /etc/mysql/conf.d/*
ADD ./etc/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./etc/supervisord_bootstrap.conf /etc/supervisor/conf.d/supervisord_bootstrap.conf



CMD ["/usr/local/bin/run.sh"]
