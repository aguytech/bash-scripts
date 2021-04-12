#!/bin/bash
#
# Provides:             vz-restore
# Short-Description:    functions over vzrestore
# Description:          functions over vzrestore

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  FUNCTION

# restore saved device to be mounted
# $1 : CTID2
# $2 : FILE
__restore_mount() {
	CTID2="$1"
	FILE="$2"

	_echoD "$FUNCNAME:$LINENO CTID2='$CTID2' FILE='$FILE' \$*='$*'"
	[ "$#" -lt 2 ] && _exite "$FUNCNAME:$LINENO missing parameters: '$#'"
	! [[ "$CTID2" && "$CTID2" =~ ^[0-9]*$ && $CTID2 -ge $S_VM_CTID_MIN && $CTID2 -le $S_VM_CTID_MAX ]] && _exite "$FUNCNAME:$LINENO wrong '$CTID2' not in $S_VM_CTID_MIN - $S_VM_CTID_MAX"

	CTIDFROM="$(echo $FILE|sed "s|^vzdump_\([0-9]*\)_.*$|\1|")"
	FILENODE="$(echo $FILE|sed "s~^vzdump_\(.*\)\.\(tgz\|tar\)$~\1~")"
	FILECONF="$S_VZ_PATH_CT_CONF/$CTID2.conf"
	FILECONFSAVE="$PATHDUMPXTRA/$FILENODE.conf"
	FILEMOUNT="$S_VZ_PATH_CT_CONF/$CTID2.mount"
	FILEMOUNTSAVE="$PATHDUMPXTRA/$FILENODE.mount"
	_echoD "$FUNCNAME:$LINENO CTIDFROM='$CTIDFROM' FILENODE='$FILENODE' PATHDUMP='$PATHDUMP' PATHDUMPXTRA='$PATHDUMPXTRA'"
	_echoD "$FUNCNAME:$LINENO FILECONF='$FILECONF' FILECONFSAVE='$FILECONFSAVE'"
	_echoD "$FUNCNAME:$LINENO FILEMOUNT='$FILEMOUNT' FILEMOUNTSAVE='$FILEMOUNTSAVE'"

	# file for devices exist
	if [ -e "$FILEMOUNT" ]; then
		MOUNTPATHS="$(grep "^SRC=.*" $FILEMOUNT|sed "s/^SRC=\(.*\)/\1/"|xargs)"
		_echoD "$FUNCNAME:$LINENO CTID2='$CTID2' MOUNTPATHS='$MOUNTPATHS'"

		# devices
		for MOUNTPATH in $MOUNTPATHS; do
			PATHPARENT=${MOUNTPATH%/*}
			PATHTMP=${MOUNTPATH##*/}
			PATH2="${PATHPARENT}/${CTID2}"
			FILEDUMP="${PATHDUMPXTRA}/${FILENODE}.${PATHTMP}.tgz"
			_echoD "$FUNCNAME:$LINENO MOUNTPATH='$MOUNTPATH'"
			_echoD "$FUNCNAME:$LINENO PATHPARENT='$PATHPARENT' PATHTMP='$PATHTMP'"
			_echoD "$FUNCNAME:$LINENO FILEDUMP='$FILEDUMP' PATH2='$PATH2'"

			# path for new ct
			if [ -e "$PATH2" ]; then
				PATH2KEEP="$PATH2-$(date +%Y%m%d-%H%M%S)"
				_evalq mv "$PATH2" "$PATH2KEEP"
				_echoE "Existing path '$PATH2' have be moved to '$PATH2KEEP'"
			fi
			_evalq mkdir -p "$PATH2"

			# dump file for device
			! [ -f "$FILEDUMP" ] && _exite "Missing dump file '$FILEDUMP' for device '$PATHTMP' for container '$CTIDFROM'" \
				|| _echoT "restore device '$PATHTMP' of container '$CTIDFROM' to '$CTID2'"

			# restore dump device
			_evalq tar xzf "$FILEDUMP" -C "$PATH2"
		done

		# file conf for new ct already exist
		if [ "$FORCECONF" ]; then
			_echoE "Existing configuration file have been overwritten"
			# configuration file
			_evalq cp "$FILECONFSAVE" "$FILECONF"
			# restore configuration file for mounted devices
			_evalq cp "$FILEMOUNTSAVE" "$FILEMOUNT"
		fi

	else
		_echoE "Unable to find configuration file '$PATHTMP' for ctid '$CTID2'.\n Please verify the configuration of the container '$CTID2'"
	fi

	# adjust IP adress in conf
	_evalq "sed -i 's/${_VM_IP_BASE}.$CTIDFROM/${_VM_IP_BASE}.$CTID2/' '$FILECONF'"
	# adjust ctid in mount
	[ "$FILEMOUNT" ] && _evalq "sed -i 's/$CTIDFROM/$CTID2/g' '$FILEMOUNT'"

	return 0
}

################################  VARIABLES

USAGE="vz-restore, function over vzrestore. by default search in all container (see [--search-name]).
Use option [--menu] for selecting manualy the container in the global list or in the results of searching.
! If you don't use option [--menu], only the newest dump is show !

<ctids> ctids is a list combinating simple ids of containers and range. ex: '100 200-210'
<all>   all use all dumped container founded

vz-restore --help

vz-restore [options] [<ctids/all>]		restore containers from <ctids/all>

vz-restore [options] -n, --new '<ctids/all>' <ctid>	restore the matched container 'ctid' to ctids in '<ctids/all>'

options:
    -y, --confirm      confirm action without prompt
    -q, --quiet        don't show any infomations except interaction informations
    -d, --debug        output in screen & in file debug informations
    -N, --new-name      give a new name (same for all containers) & don't ask it
    -K, --keep-name     keep ther old name of containers & don't ask it

    -a, --all          show all dumps, else only the lasted one by ctid.
    -m, --menu         show a menu for interactive selection of containers
    -f, --force        overwrite existing conf file, private and root directory.
    -c, --force-conf   overwrite existing conf file in dump with the saved one.
    -t, --template     restore dumping files for template in S_VZ_PATH_DUMP_TEMPLATE
    -u, --suspend      restore suspended ct from S_VZ_PATH_DUMP_SUSPEND
    -o, --snapshot     restore snapshot from S_VZ_PATH_DUMP_SNAPSHOT

    -l, --list         list available dumps
    -s, --sort <>      sort by number of followings columns: size, ctid, hostname, date, filetype
                       add above sign +/- for sens. ONLY for listing & searching (else small bug for 1)
    -n, --new '<>'     restore to new containers '<>'
    -h, --search-hname <>   search containers whith the pattern given for hostname
    -r, --search-regexp <>  search containers whith a regexp pattern for hostname
"

################################  MAIN

# openvz server
type vzrestore &>/dev/null && VZRESTORE="vzrestore" || VZRESTORE="/usr/sbin/vzrestore"
type ${VZRESTORE} &>/dev/null || _exite "unable to find vzrestore command"

type vzctl &>/dev/null && VZCTL="vzctl" || VZCTL="/usr/sbin/vzctl"
type ${VZCTL} &>/dev/null || _exite "unable to find vzctl command"

type vzlist &>/dev/null && VZLIST="vzlist" || VZLIST="/usr/sbin/vzlist"
type ${VZLIST} &>/dev/null || _exite "unable to find vzlist command"

_echoD "$_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"

SORTSTRL="-k2,2 -k4,4r"
SORTSTR="-k4,4 -k5,5r"
CTIDexist="$(${VZLIST} -aHo ctid|xargs)"
PATHDUMP="$S_VZ_PATH_DUMP"
PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"

OPTSGIVEN="$@"
OPTSSHORT="dacfh:Klmn:N:oqrstuy"
OPTSLONG="help,debug,all,force-conf,force,keep-name,list,menu,new-name:,snapshot,quiet,template,suspend,confirm,new:,search-hname:,search-regexp:,sort:"
OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- "$@" 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
eval set -- "$OPTS"

_echoD "$FUNCNAME:$LINENO OPTSGIVEN='$OPTSGIVEN' OPTS='$OPTS'"
while true; do
	case "$1" in
		--help)
			_echo "$USAGE"; _exit
			;;
		-d|--debug)
			_redirect debug
			;;
		-a|--all)
			ALL=1
			;;
		-c|--force-conf)
			FORCECONF=c
			;;
		-f|--force)
			OPTSCMD+="--$opt "
			;;
		-h|--search-hname)
			shift
			SEARCH=hname
			SEARCHSTR=$1
			;;
		-K|--keep-name)
			KEEPNAME=1
			;;
		-l|--list)
			LIST=1
			;;
		-m|--menu)
			MENU=1
			;;
		-n|--new)
			NEW=1
			shift
			CTIDSNEW="$1"
			;;
		-N|--new-name)
			shift
			NEWNAME="$1"
			;;
		-o|--snapshot)
			SNAPSHOT=o
			PATHDUMP="$S_VZ_PATH_DUMP_SNAPSHOT"
			PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"
			;;
		-q|--quiet)
			_redirect quiet
			OPTSCMD+="--quiet "
			;;
		-r|--search-regexp)
			shift
			SEARCH=regexp
			SEARCHSTR=$1
			;;
		-s|--sort)
			shift
			SORT="$1"
			;;
		-t|--template)
			PATHDUMP="$S_VZ_PATH_DUMP_TEMPLATE"
			PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"
			;;
		-u|--suspend)
			SUSPEND=u
			PATHDUMP="$S_VZ_PATH_DUMP_SUSPEND"
			PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"
			;;
		-y|--confirm)
			CONFIRM=y
			;;
		--)
			shift
			break
			;;
		*)
			_exite "Bad options: '$1' in '$OPTSGIVEN'"
			;;
	esac
	shift
done
_echoD "$FUNCNAME:$LINENO OPTSCMD='$OPTSCMD' \$*='$*'"
_echoD "$FUNCNAME:$LINENO PATHDUMP='$PATHDUMP' PATHDUMPXTRA='$PATHDUMPXTRA'"
_echoD "$FUNCNAME:$LINENO ALL='$ALL' FORCECONF='$FORCECONF' MENU='$MENU' LIST='$LIST' MENU='$MENU'"
_echoD "$FUNCNAME:$LINENO NEW='$NEW' CTIDSNEW='$CTIDSNEW' KEEPNAME='$KEEPNAME' NEWNAME='$NEWNAME'"
_echoD "$FUNCNAME:$LINENO SEARCH='$SEARCH' SEARCHSTR='$SEARCHSTR' SORT='$SORT'"
_echoD "$FUNCNAME:$LINENO SNAPSHOT='$SNAPSHOT' CONFIRM='$CONFIRM'"

# no value for containers
#[[ ! "$*" && ! "$LIST" ]] && _exite "Missing arguments for ctids '$*' for your call '$OPTSGIVEN'"

################################  SORT

[ "$NEW" ] && ! [ "$SEARCH" ] && ! [[ "$*" =~ ^[0-9]{3}$ ]] && _exite "'$CTIDSNEW' ? You have to give just one single ctid to select the container to restore !"


################################  SORT

if [ "$LIST" ]
then
	SORTADD=0
	SORTSTR=$SORTSTRL
else
	SORTADD=1
fi

if [ "$SORT" ]; then
	[[ "$SORT" =~ ^-.*$ ]] && SORTSTR="r" && SORT=${SORT#-} || SORTSTR=
	! [[ "$SORT" =~ [12345] ]] && _exite "Wrong option for sorting: '$SORT' for your call '$OPTSGIVEN'"
	SORTSTR="-k$SORT,$((SORT + SORTADD))$SORTSTR"
fi
_echoD "$FUNCNAME:$LINENO SORTSTR='$SORTSTR'"


################################  DUMPFOUND

case "$SEARCH" in
	hname)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_[0-9]*_${SEARCHSTR}_[0-9-]*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
	regexp)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_[0-9]*_${SEARCHSTR}_[0-9-]*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
	*)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_.*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
esac

# order
DUMPFOUND=$(echo $DUMPFOUND|tr " " "\n"|tr "_" " "|sort $SORTSTR|tr " " "_"|xargs)
_echoD "$FUNCNAME:$LINENO DUMPFOUND='$DUMPFOUND'"


################################  SELECT

[ "$*" ] && CTIDSELECT="$*" || CTIDSELECT="all"

if [ "$CTIDSELECT" != "all" ]; then
	CTIDSELECT="$(_vz_ctids_clean "$CTIDSELECT")"

	# minus DUMPFOUND by CTIDSELECT
	for DUMP in $DUMPFOUND; do
		CTID=$(echo $DUMP|awk -F "_" '{print $3}')
		#_echoD "$FUNCNAME:$LINENO CTID=$CTID DUMP=$DUMP"
		[ "${CTIDSELECT/$CTID/}" != "$CTIDSELECT" ] && DUMPSELECT+="$DUMP "
	done
else
	DUMPSELECT=$DUMPFOUND
fi

_echoD "$FUNCNAME:$LINENO CTIDSELECT='$CTIDSELECT' DUMPSELECT='$DUMPSELECT'"


# select the uniq new ctid in DUMPSELECT
if [[ ! "$ALL" || "$NEW" ]]; then
	DUMPTMP=$DUMPSELECT
	DUMPSELECT=
	HOSTTMP=
	CTIDTMP=
	for DUMP in $DUMPTMP; do
		CTID=$(echo $DUMP|awk -F "_" '{print $2}')
		host=$(echo $DUMP|awk -F "_" '{print $3}')
		! [[ "$CTID" == "$CTIDTMP" && "$host" == "$HOSTTMP" ]] && DUMPSELECT+="$DUMP "
		HOSTTMP=$host
		CTIDTMP=$CTID
	done
fi
_echoD "$FUNCNAME:$LINENO DUMPSELECT='$DUMPSELECT'"


################################ no DUMPSELECT

! [ "$DUMPSELECT" ] && _exite "No containers for your selection '$OPTSGIVEN'"


################################  LIST

if [ "$LIST" ]; then
	echo $DUMPSELECT|tr " " "\n"|awk -F "_" '{ print $1 " " $3 " " $4 " " $5 " " $6}'|sort $SORTSTR|column -t >&5
	_exit 0
fi

################################  NEW

if [ "$NEW" ]; then
	# DUMPSPROC
	CTIDSNEW="$(_vz_ctids_clean "$CTIDSNEW")"
	FILE="$(echo $DUMPSELECT|awk -F "_" '{ print $2"_"$3"_"$4"_"$5"."$6 }')"
	for CTID in $CTIDSNEW; do
		[ "${CTIDexist/$CTID/}" == "$CTIDexist" ] && DUMPSPROC[$CTID]="$FILE" || NOCTREPLACE+="$CTID "
	done
else

	################################ menu

	if [ "$MENU" ]; then
		declare -A DUMPMENU
		declare -A DUMPCTID

		# associations
		assocs=
		while ! [[ "$assocs" =~ ^q|p$ ]]; do
			#refresh existings ctid
			CTIDexist="$(${VZLIST} -aHo ctid|xargs)"

			# list of temporary associations
			ASSOCLIST=
			for CTID in ${!DUMPCTID[*]}; do
				ASSOCLIST+="${DUMPCTID[$CTID]}-$CTID\n"
			done
			_echoD "$FUNCNAME:$LINENO !DUMPCTID='${!DUMPCTID[*]}' ASSOCLIST='$ASSOCLIST'"

			# list of dumps selected & available for menu
			MENU=
			i=1
			for DUMP in $DUMPSELECT; do
				DUMPMENU[$i]="$DUMP"
				DUMPCTID_=" ${DUMPCTID[*]} "
				_echoD "$FUNCNAME:$LINENO DUMPCTID_='$DUMPCTID_' i='$i'"
				[ "${DUMPCTID_}" != "${DUMPCTID_/" $i "/}" ] \
					&& MENU+="${blueb}$i)\t$(echo $DUMP|awk -F "_" '{ print $1 " " $3 " " $4 " " $5 " " $6 }')${cclear}\n" \
					|| MENU+="${white}$i)\t$(echo $DUMP|awk -F "_" '{ print $1 " " $3 " " $4 " " $5 " " $6 }')${cclear}\n"
				let i++
			done
			_echoD "$FUNCNAME:$LINENO DUMPMENU=${DUMPMENU[*]}"
			_echoD "$FUNCNAME:$LINENO !DUMPCTID[*]='${!DUMPCTID[*]}' DUMPCTID[*]='${DUMPCTID[*]}'"

			# menu
			_echo "---------------------------------------------------------"
			_echo "$(echo -e $MENU|column -t)"
			_echo "---------------------------------------------------------"
			_echo "ctids existing: $CTIDexist"
			_echo "---------------------------------------------------------"
			[ "$ASSOCLIST" ] && _echoW "Your actual assocs: ${cclear}${blueb}$(echo -e $ASSOCLIST|sort -n)"

			_echo "Your assocs [menu-ctid] (q: quit / p: process): "
			read assocs >&4
			_echoD "$FUNCNAME:$LINENO assocs=$assocs"

			# quit
			[ "$assocs" == "q" ] && _exit

			# not process
			if [ "$assocs" != "p" ]; then
				for assoc in $assocs; do
					# good association
					if [[ "$assoc" =~ ^[0-9]*-[0-9]*$ ]]; then
						id=${assoc%-*}
						CTID=${assoc#*-}

						# existing id in menu
						LISTID=${!DUMPMENU[*]}
						if [ "${LISTID/$id/}" != "${LISTID}" ]; then
							# ctid already exists
							if [ "${CTIDexist/$CTID/}" == "${CTIDexist}" ]; then
								# wrong ctid
								if [[ "$CTID" =~ ^[0-9]{3}$ && $CTID -ge $S_VM_CTID_MIN && $CTID -le $S_VM_CTID_MAX ]]; then
									# add association
									if [ "${DUMPCTID[$CTID]+_}" ] && [ "${DUMPCTID[$CTID]}" == "$id" ];
									then unset DUMPCTID[$CTID]
									else DUMPCTID[$CTID]=$id
									fi
								else
									_echoE "Wrong association '$assoc', container '$CTID' must be between $S_VM_CTID_MIN-$S_VM_CTID_MAX"
								fi
							else
								_echoE "Wrong association '$assoc', container '$CTID' already exists"
							fi
						else
							_echoE "Wrong association '$assoc', menu '$id' doesn't exists"
						fi
					else
						_echoE "Wrong syntax for association '$assoc'"
					fi
				done
				_echoD "$FUNCNAME:$LINENO !DUMPCTID[*]='${!DUMPCTID[*]}' DUMPCTID[*]='${DUMPCTID[*]}'"
			fi
		done

		# DUMPSPROC
		_echoD "$FUNCNAME:$LINENO DUMPMENU keys=${!DUMPMENU[*]} values=${DUMPMENU[*]}"
		_echoD "$FUNCNAME:$LINENO DUMPCTID keys=${!DUMPCTID[*]} values=${DUMPCTID[*]}"
		for CTID in ${!DUMPCTID[*]}; do
			FILE=${DUMPMENU[${DUMPCTID[$CTID]}]}
			FILE="$(echo $FILE|awk -F "_" '{ print $2"_"$3"_"$4"_"$5"."$6 }')"
			DUMPSPROC[$CTID]=$FILE
		done

	################################ simple

	else
		# DUMPSPROC
		#_echoD "$FUNCNAME:$LINENO $(date +%s.%N)"
		for DUMP in $DUMPSELECT; do
			CTID="$(echo $DUMP|awk -F "_" '{ print $3 }')"
			FILE="$(echo $DUMP|awk -F "_" '{ print $2"_"$3"_"$4"_"$5"."$6 }')"
			#CTID="$(echo $DUMP| sed "s/^vzDUMP_\([0-9]*\).*/\1/")"
			#FILE=$(echo $DUMP|sed "s/^[0-9]*_\(.*\)_\([a-z]*\)$/\1.\2/")
			[ "${CTIDexist/$CTID/}" == "$CTIDexist" ] && DUMPSPROC[$CTID]="$FILE" || NOCTREPLACE+="$CTID "
		done
		#_echoD "$FUNCNAME:$LINENO $(date +%s.%N)"
	fi
fi

_echoD "$FUNCNAME:$LINENO DUMPSPROC keys=${!DUMPSPROC[*]} values=${DUMPSPROC[*]}"

# report existing containers
[ "$NOCTREPLACE" ] && _echoE "Containers are skipped, they are already exists: $NOCTREPLACE"

# dump show
COUNT=0
DUMPSHOW=
for CTID in ${!DUMPSPROC[*]}; do
	DUMPSHOW+="$CTID <- ${DUMPSPROC[$CTID]}\n"
	let COUNT++
done
# confirm
if [ ! "$CONFIRM" ]; then
	[ "$DUMPSHOW" ] && _echoT "$(echo -e $DUMPSHOW|sort -n|column -t)"
	_askno "${whiteb}$COUNT dump(s) to restore ? y(n) ${cclear}"
	[ "$_ANSWER" != "y" ] && _exit 0
fi

# commands
for CTID in ${!DUMPSPROC[*]}; do
	# restore container
	_echoI "create $CTID"
	_eval "${VZRESTORE} \"$PATHDUMP/${DUMPSPROC[$CTID]}\" $CTID"

	_echoD "$FUNCNAME:$LINENO SUSPEND='$SUSPEND' SNAPSHOT='$SNAPSHOT'"
	if ! [[ $SUSPEND || $SNAPSHOT ]]; then
		# restore devices
		_evalq "__restore_mount $CTID ${DUMPSPROC[$CTID]}"
	fi
done

# rename & start ct & adjust name in ct
for CTID in ${!DUMPSPROC[*]}; do
    _echoI "adjust $CTID"

    NAME="$(${VZLIST} -aHo hostname $CTID)"
    NAME=${NEWNAME:-$NAME}
    ! [[ "$NEWNAME" || "$KEEPNAME" ]] && _askno "Give a new hostname for container '$CTID' ($NAME) "

    # rename ct
    _echoi "Renaming $CTID"
    _evalq "${VZCTL} set $CTID --hostname ${_ANSWER:-$NAME} --save"

    # start ct
    _echoi "start $CTID"
    _evalq "${VZCTL} start $CTID"

    # ajust mailname
    _echoi "Adjust $CTID"
    FILE=/etc/mailname
    _evalq "${VZCTL} exec $CTID 'echo \$HOSTNAME > $FILE'"
    # ajust exim4
    FILE=/etc/exim4/update-exim4.conf.conf
    _evalq "${VZCTL} exec $CTID '[ -f "$FILE" ] && sed -i \"s|^dc_readhost=.*|dc_readhost='\''\$HOSTNAME'\''|\" $FILE'"
done

_exit 0
