#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

if [ "${PXC_SST_PASSWORD}" == "**ChangeMe**" -o -z "${PXC_SST_PASSWORD}" ]; then
   echo "*** ERROR: you need to define PXC_SST_PASSWORD environment variable - Exiting ..."
   exit 1
fi

if [ "${PXC_ROOT_PASSWORD}" == "**ChangeMe**" -o -z "${PXC_ROOT_PASSWORD}" ]; then
   echo "*** ERROR: you need to define PXC_ROOT_PASSWORD environment variable - Exiting ..."
   exit 1
fi

if [ "${SERVICE_NAME}" == "**ChangeMe**" -o -z "${SERVICE_NAME}" ]; then
   echo "*** ERROR: you need to define SERVICE_NAME environment variable - Exiting ..."
   exit 1
fi

# Find the IP address assigned to eth0
export MY_RANCHER_IP=`ip addr | grep inet | grep eth0 | tail -1 | awk '{print $2}' | awk -F\/ '{print $1}'`
if [ -z "${MY_RANCHER_IP}" ]; then
   echo "*** ERROR: Could not determine this container Rancher IP - Exiting ..."
   exit 1
fi
echo "=> Container IP: ${MY_RANCHER_IP}"

# Find my Hostname...
export MY_HOSTNAME=`hostname`
echo "=> Container Host: ${MY_HOSTNAME}"

# Update the Percona config with our IP address...
echo "=> Updating Percona configuration: wsrep_node_address=${MY_RANCHER_IP}, wsrep_node_name=${MY_HOSTNAME}"
perl -p -i -e "s/MY_RANCHER_IP/${MY_RANCHER_IP}/g" ${PXC_CONF}
perl -p -i -e "s/MY_HOSTNAME/${MY_HOSTNAME}/g" ${PXC_CONF}

# Configure the cluster (replace required parameters)
echo "=> Waiting to join PXC cluster"
	
export PXC_NODES=`dig +short ${SERVICE_NAME} | sort`
export CURRENT_NODE_COUNT=`echo ${PXC_NODES} | wc -w`
while [ ${CURRENT_NODE_COUNT} -lt ${SERVICE_NODE_COUNT} ]; do

	# Should we bootstrap ourselves?
	if [ -f /etc/mysql/do_bootstrap ]; then
		break;
	fi

   echo "*** WARNING: Not enough nodes found to form a cluster (${CURRENT_NODE_COUNT}/${SERVICE_NODE_COUNT}), retry in ${NODE_COUNT_FIRST_RETRY_SECONDS} seconds..."
   sleep ${NODE_COUNT_FIRST_RETRY_SECONDS}
   
   export PXC_NODES=`dig +short ${SERVICE_NAME} | sort`
   export CURRENT_NODE_COUNT=`echo ${PXC_NODES} | wc -w`
done

# Found enough nodes to continue in a cluster...
printf "=> Nodes found:\n${PXC_NODES}\n"
export PXC_NODES=`echo ${PXC_NODES} | sed "s/ /,/g"`

# Update our root user password for SSH...
echo "=> Updating root password..."
echo "root:${PXC_ROOT_PASSWORD}" | chpasswd

# Update the Percona config with our defined root user password...
echo "=> Updating SST password..."
perl -p -i -e "s/PXC_SST_PASSWORD/${PXC_SST_PASSWORD}/g" ${PXC_CONF}

# Ensure the data directory is owned by the mysql user...
echo "=> Setting permissions on ${PXC_VOLUME}"
chown -R mysql:mysql ${PXC_VOLUME}

# Loop until a cluster is joined OR asked to bootstrap...
BOOTSTRAPED=false

# Should we bootstrap ourselves?
while [ ${BOOTSTRAPED} != "true" ]; do

	if [ -f /etc/mysql/do_bootstrap ]; then
		break;
	fi	
	
	# If the bootstrapped file is missing, check all other nodes...
	if [ ! -e ${PXC_CONF_FLAG} ]; then
	
		# Ask other containers if they're already configured
		# If so, I'm joining the cluster...

		for node in `echo "${PXC_NODES}" | sed "s/,/ /g"`; do
			# Skip myself
			if [ "${MY_RANCHER_IP}" == "${node}" ]; then
				continue
			fi
			# Check if node is already initializated - that means the cluster has already been bootstraped 
			if sshpass -p ${PXC_ROOT_PASSWORD} ssh ${SSH_OPTS} ${SSH_USER}@${node} "[ -e ${PXC_BOOTSTRAP_FLAG} ]" >/dev/null 2>&1; then
				echo "=> Node ${node} is bootstrapped!"
				BOOTSTRAPED=true
				
				# Update Percona config with addresses of the other cluster nodes...
				echo "=> Updating WRESP node addresses"
				change_pxc_nodes.sh "${PXC_NODES}"

				break
			fi
		done

		# If any other nodes have indicated that the cluster is up, join the cluster...
		if ${BOOTSTRAPED}; then
			echo "=> Joining the cluster..."
			join-cluster.sh || exit 1
			break;
		fi
	else
	   # If this container is already configured, just start it
	   break
	fi
	
	echo "=> Unable to join a cluster! Retry in ${NODE_COUNT_FIRST_RETRY_SECONDS} seconds..."
	sleep ${NODE_COUNT_FIRST_RETRY_SECONDS}	
	
done;

# Should we break out and bootstrap ourselves?
if [ -f /etc/mysql/do_bootstrap ]; then
	rm -f /etc/mysql/do_bootstrap || true
	echo "=> Bootstrapping this node..."
	bootstrap-pxc.sh || exit 1
else
	# Done! Fire up our services and get to work!
	echo "=> Starting supervisord..."
	/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
fi
