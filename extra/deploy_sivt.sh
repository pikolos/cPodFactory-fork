#!/bin/bash
#bdereims@vmware.com

. ./env

[ "${1}" == "" ] && echo "usage: ${0} <cPod Name> <owner email>" && exit 1

if [ -f "${1}" ]; then
        . ./${COMPUTE_DIR}/"${1}"
else
        SUBNET=$( ./${COMPUTE_DIR}/cpod_ip.sh ${1} )

        [ $? -ne 0 ] && echo "error: file or env '${1}' does not exist" && exit 1

        CPOD=${1}
	unset DATASTORE
        . ./${COMPUTE_DIR}/cpod-xxx_env
fi

### functions ####

source ./extra/functions.sh

### Local vars ####

HOSTNAME=${HOSTNAME_SIVT}
#NAME=${NAME_SIVT}
IP=${IP_SIVT}
OVA=${OVA_SIVT}

#AUTH_DOMAIN="vsphere.local"
AUTH_DOMAIN=${DOMAIN}

###################

[ "${HOSTNAME_SIVT}" == ""  -o "${OVA_SIVT}" == "" -o "${IP_SIVT}" == "" ] && echo "missing parameters - please source version file !" && exit 1


CPOD_NAME="cpod-$1"
NAME_HIGHER=$( echo ${1} | tr '[:lower:]' '[:upper:]' )
CPOD_NAME_LOWER=$( echo ${CPOD_NAME} | tr '[:upper:]' '[:lower:]' )
LINE=$( sed -n "/${CPOD_NAME_LOWER}\t/p" /etc/hosts | cut -f3 | sed "s/#//" | head -1 )
if [ "${LINE}" != "" ] && [ "${LINE}" != "${2}" ]; then
        echo "Error: You're not allowed to deploy"
#        ./extra/post_slack.sh ":wow: *${2}* you're not allowed to deploy in *${NAME_HIGHER}*"
        exit 1
fi

CPOD_PORTGROUP="${CPOD_NAME_LOWER}"
VAPP="cPod-${NAME_HIGHER}"

NAME="${VAPP}-sivt"
VLAN=$( grep -m 1 "${CPOD_NAME_LOWER}\s" /etc/hosts | awk '{print $1}' | cut -d "." -f 4 )

STATUS=$( ping -c 1 ${IP} 2>&1 > /dev/null ; echo $? )
STATUS=$(expr $STATUS)
if [ ${STATUS} == 0 ]; then
        echo "Error: Something has the same IP."
#        ./extra/post_slack.sh ":wow: Are you sure that VCSA is not already deployed in ${1}. Something have the same @IP."
        exit 1
fi

PASSWORD=$( ./${EXTRA_DIR}/passwd_for_cpod.sh ${1} )

export MYSCRIPT=/tmp/$$

cat << EOF > ${MYSCRIPT}
export LANG=en_US.UTF-8
cd /root/cPodFactory/ovftool
./ovftool --acceptAllEulas --X:injectOvfEnv --allowExtraConfig --powerOn  --sourceType=OVA  \
--X:logFile=/tmp/ovftool.log --X:logLevel=verbose --X:logTransferHeaderData \
--name=${NAME} --datastore=${VCENTER_DATASTORE} --noSSLVerify \
--diskMode=thin --net:"Appliance Network"="${CPOD_PORTGROUP}" \
--prop:appliance.ntp=${GATEWAY} \
--prop:sivt.password="${PASSWORD}" \
--prop:vami.gateway.Service_Installer_for_VMware_Tanzu=${GATEWAY} \
--prop:vami.domain.Service_Installer_for_VMware_Tanzu="${HOSTNAME}.${DOMAIN}" \
--prop:appliance.harbor.fqdn="${HOSTNAME}.${DOMAIN}" \
--prop:vami.searchpath.Service_Installer_for_VMware_Tanzu=${DOMAIN} \
--prop:vami.DNS.Service_Installer_for_VMware_Tanzu=${DNS} \
--prop:vami.ip0.Service_Installer_for_VMware_Tanzu=${IP} \
--prop:vami.netmask0.Service_Installer_for_VMware_Tanzu=255.255.255.0 \
${OVA} \
'vi://${VCENTER_ADMIN}:${VCENTER_PASSWD}@${VCENTER}/${VCENTER_DATACENTER}/host/${VCENTER_CLUSTER}/Resources/cPod-Workload/${VAPP}'
EOF

sh ${MYSCRIPT}

echo "Adding entries into hosts of ${CPOD_NAME_LOWER}."
add_to_cpodrouter_hosts "${IP_SIVT}" "sivt" ${CPOD_NAME_LOWER}
add_to_cpodrouter_hosts "10.${VLAN}.1.2" "nsxalb01" ${CPOD_NAME_LOWER}

#rm ${MYSCRIPT}
