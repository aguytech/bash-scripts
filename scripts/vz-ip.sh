#!/bin/bash
#
# Provides:             vz-ip
# Short-Description:    functions over vzctl to manipulate containers IP
# Description:          functions over vzctl to manipulate containers IP

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions.sh}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  FUNCTION

# create list of containers & analyse it
__ctid_analyse()
{
	# list initialize
	[ "$*" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$*")"

	# list empty
	[ ! "$CTIDLIST" ] && _exite "No valid containers for your selection '$*'"

	# define final list
	for CTID in $CTIDLIST
	do

		# ctid exist
		if [ "${CTIDEXIST/$CTID/}" != "$CTIDEXIST" ]; then

			# ctid in selection
			if [ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ]; then

				# ctid with ip
				if [ "${CTIDIPEXIST/$CTID/}" == "$CTIDIPEXIST" ]; then
					CTIDNOIP+="$CTID "
				else
					IPS+="$CTID - $(${VZLIST} -Ho ip $CTID |xargs |tr "\n" "&")"
					CTIDIP+="$CTID "
				fi

			else
				! [ "$ALL" ] && CTIDNORUN+="$CTID "
			fi

		elif [ "$ALL" ]; then
			CTIDNOEXIST+="$CTID "
		fi

	done
	IPS=${IPS%&}
	_echoD "$FUNCNAME:$LINENO CTIDLIST=$CTIDLIST CTIDEXIST=$CTIDEXIST CTIDSELECT=$CTIDSELECT CTIDIPEXIST=$CTIDIPEXIST"
	_echoD "$FUNCNAME:$LINENO CTIDIP=$CTIDIP CTIDNOIP=$CTIDNOIP CTIDIP=$CTIDIP"

	return 0
}

################################  VARIABLES

USAGE="vz-ip : manage ip for containers, default selection is made only with running containers (use -a,all for all containers)
vz-ip --help

vz-ip [action] [options] [ctids / all]
    ctids is a list of ids containing in brackets and can be a range. ex : '100 200-210'

action
    list            list containers IP
    add             add IP to containers
    del             remove IP from containers

options:
    -a, --all       selection is made with all available containers else only running containers
    -S, --stopped   selection is made with only stopped containers
    -r, --replace   replace existing Ips (for add)
    -v, --view      for action list, view IPs
    -y, --confirm   confirm action without prompt
    -q, --quiet     don't show any infomations except interaction informations
    -d, --debug     output in screen & in file debug informations
"

################################  MAIN

# openvz server
type vzctl &>/dev/null && VZCTL="vzctl" || VZCTL="/usr/sbin/vzctl"
type ${VZCTL} &>/dev/null || _exite "unable to find vzctl command"

type vzlist &>/dev/null && VZLIST="vzlist" || VZLIST="/usr/sbin/vzlist"
type ${VZLIST} &>/dev/null || _exite "unable to find vzlist command"

_echoD "$FUNCNAME:$LINENO $_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"

CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
CTIDSELECT="$(${VZLIST} -Ho ctid 2>/dev/null|xargs)"
CTIDIPEXIST="$(${VZLIST} -aHo ctid,ip |grep ".*[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$" |awk '{print $1}' |xargs)"

OPTSGIVEN="$@"
OPTSSHORT="daqrSvy"
OPTSLONG="help,debug,all,quiet,replace,stopped,view,confirm"
OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- "$@" 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
eval set -- "$OPTS"

_echoD "$FUNCNAME:$LINENO OPTSGIVEN='$OPTSGIVEN' OPTS='$OPTS'"
while true; do
	case "$1" in
		--help)
			_echo "$USAGE"; _exit
			;;
		-d|--debug)
			DEBUG=d
			_redirect debug
			;;
		-a|--all)
			ALL=a
			CTIDSELECT="$CTIDEXIST"
			;;
		-q|--quiet)
			QUIET=q
			_redirect quiet
			;;
		-r|--replace)
			replace=1
			;;
		-S|--stopped)
			STOPPED=S
			CTIDSELECT="$(${VZLIST} -SHo ctid|xargs)"
			;;
		-v|--view)
			VIEW=v
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
_echoD "$FUNCNAME:$LINENO CTIDSELECT=$CTIDSELECT \$*=$*"

ACTION="$1"
shift
_echoD "$FUNCNAME:$LINENO ACTION=$ACTION \$*='$*'"

# Action
case "$ACTION" in
	--help)
		_echo "$USAGE"; _exit
		;;
	list)
		# analyse ctids
		[ "$*" ] && __ctid_analyse $* || __ctid_analyse all

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDNOEXIST='$CTIDNOEXIST' CTIDNOIP='$CTIDNOIP' CTIDIP='$CTIDIP'"
		[ "$CTIDNOEXIST" ] && _echoW "Containers does not exist: $CTIDNOEXIST"
		[ "$CTIDNORUN" ] && _echoW "Containers does not running: $CTIDNORUN"
		[ "$CTIDNOIP" ] && _echoW "IP doesn't exist for: $CTIDNOIP"
		[ "$CTIDIP" ] && _echoW "IP existing for containers: ${cclear}${blueb}$CTIDIP"
		[[ "$IPS" && "$VIEW" ]] && echo -e ${IPS//"&"/"\n"} >&5
		;;
	add)
		# analyse ctids
		[ "$*" ] && __ctid_analyse $* || _exite "Missing ctids in options '$OPTSGIVEN'"

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDNOEXIST='$CTIDNOEXIST' CTIDIP='$CTIDIP' CTIDNOIP='$CTIDNOIP'"
		[ "$CTIDNOEXIST" ] && _echoW "Containers does not exist: $CTIDNOEXIST"
		[ "$CTIDNORUN" ] && _echoW "Containers does not running: $CTIDNORUN"
		[ "$CTIDIP" ] && _echoW "IPs already exist for: $CTIDIP"

		CTIDCMD=$CTIDNOIP
		# replace
		[ "$replace" ] && CTIDCMD+="$CTIDIP " && CTIDCMD="$(echo $CTIDCMD |tr " " "\n" |sort |xargs)"

		# confirm
		if [ "$CTIDCMD" ]; then
			if [ ! "$CONFIRM" ]; then
				_echoW "Containers to $ACTION IPs: ${cclear}${blueb}$CTIDCMD"
				_askyn "confirm ?" && [ "$_ANSWER" == "n" ] && _exit
			fi
		else
			_exite "No containers available with no iptables rules"
		fi

		# commands
		for CTID in $CTIDCMD
		do
			CMD="${VZCTL} set $CTID"
			[ "$replace" ] && CMD+=" --ipdel all"
			CMD+=" --ipadd ${_VM_IP_BASE}.${CTID} --save"
			_echoT "$CTID - $ACTION ${_VM_IP_BASE}.${CTID}"
			_eval "$CMD"

			# ipt
			_eval "vzipt $ACTION -y$ALL$DEBUG$QUIET $CTID"
		done
	   ;;
	del)
		# analyse ctids
		[ "$*" ] && __ctid_analyse $* || _exite "Missing ctids in options '$OPTSGIVEN'"

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDNOEXIST='$CTIDNOEXIST' CTIDNOIP='$CTIDNOIP' CTIDIP='$CTIDIP'"
		#[ "$CTIDNOEXIST" ] && _echoW "Containers does not exist        : $CTIDNOEXIST"
		[ "$CTIDNORUN" ] && _echoW "Containers does not running      : $CTIDNORUN"
		[ "$CTIDNOIP" ] && _echoW "Ips doesn't exist		  : $CTIDNOIP"

		 # confirm
		if [ "$CTIDIP" ]; then
			if [ ! "$confirm" ]; then
				_echoW "Containers to $ACTION ALL IPS        : ${cclear}${blueb}$CTIDIP"
				_askyn "confirm ?" && [ "$_ANSWER" == "n" ] && _exit
			fi
		else
			_exite "No containers available with iptables rules"
		fi

		# commands
		for CTID in $CTIDIP
		do
			_echoT "$CTID - $ACTION all ips"
			_eval "${VZCTL} set $CTID --ipdel all --save"

			# ipt
			_eval "vz-iptables $ACTION -y$ALL$DEBUG$QUIET $CTID"
		done
		;;
	* )
		_exite "Wrong action: '$ACTION' for arguments '$OPTSGIVEN'"
		;;
esac

_exit 0
