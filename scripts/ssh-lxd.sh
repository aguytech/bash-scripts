#!/bin/bash
#
# Provides:                ssl-lxd.sh
# Short-Description:       connect with ssh to LXD containers & his host
# Description:             connect with ssh to LXD containers & his host

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

###################################### Do not touch after this

if [[ "$1" && "$1" =~ ^[0-9]{3}$ && $1 -ge $S_VM_CTID_MIN && $1 -le $S_VM_CTID_MAX ]]; then
	cmd="ssh ${S_VM_SSH_USER}@${_VM_IP_BASE}.$1 -p${S_SSH_PORT}"
	_echoD $cmd
	eval $cmd
	exit
fi

# conf
declare -A Ip; declare -A User; declare -A Port; declare -A Cert
red='\e[31m';

# variables
while read line
do
	if [ "$line" ]; then
		id=${line%% *}
		status=${line##* }
		name=$(echo $line|awk '{print $2}')
		ip=$(echo $line|awk '{print $3}')
		key=$id'.'$name

		#echo "$ctid - $name - $ip - $status"
		[ "$status" == "running" ] && Ip[$key]="$ip" && User[$key]="$S_VM_SSH_USER" && Port[$key]="$S_SSH_PORT"
	fi
done <<< "$(vzlist -aHo ctid,hostname,ip,status)"

# menu
if [ "$(echo ${!Ip[@]})" ]
then
	select opt in $(printf '%s\n' "${!Ip[@]}" | sort -s)
	do
		if [ "$opt" ]
		then
			cmd="ssh ${User[$opt]}@${Ip[$opt]} -p${Port[$opt]}"
			# echo $cmd
			eval $cmd
		else
			echo -e "\nVeuillez saisir une option valide en recommençant"
		fi
	break
	done
else
	echo -e  "\nNo containers are running"
fi

exit 0
