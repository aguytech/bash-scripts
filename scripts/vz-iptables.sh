#!/bin/bash
#
# Provides:             vz-iptables
# Short-Description:    manipulate iptables rules for openvz
# Description:          manipulate iptables rules for openvz

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions.sh}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  VARIABLES

USAGE="vz-iptables : manage iptables rules for containers, default selection is made only with running containers (use -a,all for all containers)
vz-iptables --help

vz-iptables [actions] [options] [ctids / all]
    ctids is a list of ids containing in brackets and can be a range. ex : '100 200-210'

actions
    list           list iptables rules for containers, by default use only running container (else use --all)
    add            add ipatbles rules for containers, by default use only running container (else use --all)
    del            remove ipatbles rules for containers, by default use only stopped container (else use --all)

options:
    -a, --all      selection is made with all available containers (not only running or stopped container)
    -S, --stopped  selection is made with only stopped containers
    -v, --view     for action list, view iptables rules
    -y, --confirm  confirm action without prompt
    -q, --quiet    don't show any infomations except interaction informations
    -d, --debug    output in screen & in file debug informations

"

################################  MAIN

# openvz server
type vzlist &>/dev/null && VZLIST="vzlist" || VZLIST="/usr/sbin/vzlist"
type ${VZLIST} &>/dev/null || _exite "unable to find vzlist command"

_echoD "$FUNCNAME:$LINENO $_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"

# test S_SSH_NAT
[ "$S_SSH_NAT" != "ON" ] && _echoD "$FUNCNAME:$LINENO bypass rules from S_SSH_NAT" && _exit 0

IPT="iptables -t nat"

OPTSGIVEN="$@"
OPTSSHORT="daqSvy"
OPTSLONG="help,debug,all,quiet,stopped,view,confirm"
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
			ALL=all
			;;
		-q|--quiet)
			_redirect quiet
			;;
		-S|--stopped)
			STOPPED=S
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
_echoD "$FUNCNAME:$LINENO \$*='$*'"

ACTION="$1"
shift
_echoD "$FUNCNAME:$LINENO ACTION=$ACTION \$*='$*'"

# Action
case "$ACTION" in
	--help)
		_echo "$USAGE"; _exit
		;;
	list)
		# exist
		CTIDEXISTING="$(VZLIST -aHo ctid|xargs)"
		if [[ "$*" == "all" || ! "$*" ]]; then
			CTIDEXIST="$CTIDEXISTING"
			CTIDNOEXIST=
		else
			CTIDEXISTING=
			CTIDLIST="$(_vz_ctids_clean "$* ")"
			for CTID in $CTIDLIST; do
				[ "${CTIDEXISTING/$CTID/}" != "$CTIDEXISTING" ] && CTIDEXIST+="$CTID " || CTIDNOEXIST+="$CTID "
			done
		fi

		# running
		CTIDRUNNING="$(VZLIST -Ho ctid 2>/dev/null|xargs)"
		if [ "$ALL" ]; then
			CTIDRUN="$CTIDEXIST"
			CTIDNORUN=
		else
			for CTID in $CTIDEXIST; do
				[ "${CTIDRUNNING/$CTID/}" != "$CTIDRUNNING" ] && CTIDRUN+="$CTID " || CTIDNORUN+="$CTID "
			done
		fi

		# existing rules
		CTIDRULEEXIST="$(iptables-save|grep "^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE[0-9]* .* "|sed "s/^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE\([0-9]*\) .*$/\1/" |sort -u |xargs)"
		CTIDRULE=
		CTIDNORULE=
		for CTID in $CTIDRUN; do
			if [ "${CTIDRULEEXIST/$CTID/}" != "$CTIDRULEEXIST" ]; then
				CTIDRULE+="$CTID "
				RULES+="$(iptables-save |grep "^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE$CTID* .* " |tr "\n" "^ ")"
			else
				CTIDNORULE+="$CTID "
			fi
		done

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDEXIST='$CTIDEXIST' CTIDNOEXIST='$CTIDNOEXIST' CTIDRULE='$CTIDRULE' CTIDNORULE='$CTIDNORULE' CTIDRUN='$CTIDRUN' CTIDNORUN='$CTIDNORUN'"
		[ "$CTIDNOEXIST" ] && _echoW "Containers does not exist     : $CTIDNOEXIST"
		[ "$CTIDNORULE" ] && _echoW "Rules doesn't exist           : $CTIDNORULE"
		[ "$CTIDNORUN" ] && _echoW "Containers does not running   : $CTIDNORUN"
		[ "$CTIDRULE" ] && _echoW "Rules existing for containers : ${cclear}${blueb}$CTIDRULE"
		[[ "$RULES" && "$VIEW" ]] && echo -e ${RULES//"^"/"\n"} >&5

		_exit 0
		;;
	add)
		# no citd
		! [ "$*" ] && _exite "Missing ctids: '$*' for arguments '$OPTSGIVEN'"

		# exist
		CTIDEXISTING="$(VZLIST -aHo ctid|xargs)"
		if [ "$*" == "all" ]; then
			CTIDEXIST="$CTIDEXISTING"
			CTIDNOEXIST=
		else
			CTIDEXIST=
			CTIDLIST="$(_vz_ctids_clean "$* ")"
			for CTID in $CTIDLIST; do
				[ "${CTIDEXISTING/$CTID/}" != "$CTIDEXISTING" ] && CTIDEXIST+="$CTID " || CTIDNOEXIST+="$CTID "
			done
		fi
		_echoD "$FUNCNAME:$LINENO CTIDEXIST='$CTIDEXIST' CTIDNOEXIST='$CTIDNOEXIST'"

		# no existing rules
		CTIDRULEEXIST="$(iptables-save|grep "^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE[0-9]* .* " |sed "s/^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE\([0-9]*\) .*$/\1/" |sort -u |xargs)"
		CTIDRULE=
		CTIDNORULE=
		for CTID in $CTIDEXIST; do
			[ "${CTIDRULEEXIST/$CTID/}" != "$CTIDRULEEXIST" ] && CTIDRULE+="$CTID " || CTIDNORULE+="$CTID "
		done
		_echoD "$FUNCNAME:$LINENO CTIDRULE='$CTIDRULE' CTIDNORULE='$CTIDNORULE'"

		# running
		CTIDRUNNING="$(${VZLIST} -Ho ctid 2>/dev/null|xargs)"
		if [ "$ALL" ]; then
			CTIDRUN="$CTIDNORULE"
			CTIDNORUN=
		else
			for CTID in $CTIDNORULE; do
				[ "${CTIDRUNNING/$CTID/}" != "$CTIDRUNNING" ] && CTIDRUN+="$CTID " || CTIDNORUN+="$CTID "
			done
		fi

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDEXIST='$CTIDEXIST' CTIDNOEXIST='$CTIDNOEXIST' CTIDRULE='$CTIDRULE' CTIDNORULE='$CTIDNORULE' CTIDRUN='$CTIDRUN' CTIDNORUN='$CTIDNORUN'"
		#[ "$CTIDNOEXIST" ] && _echoW "Containers does not exist        : $CTIDNOEXIST"
		[ "$CTIDRULE" ] && _echoW "Rules already exist for	       : $CTIDRULE"
		[ "$CTIDNORUN" ] && _echoW "Containers does not running      : $CTIDNORUN"

		# confirm
		if [ "$CTIDRUN" ]; then
			if [ ! "$CONFIRM" ]; then
				_echoW "Containers to $ACTION iptables rules : ${cclear}${blueb}$CTIDRUN"
				_askyn "confirm ?" && [ "$_ANSWER" == "n" ] && _exit
			fi
		else
			_exit 0
		fi

		# execute
		for CTID in $CTIDRUN; do
			[ "$VIEW" ] && _echoT "add iptables rule for $CTID"
			_eval "$IPT -A PREROUTING -d ${_IPTHIS}/32 -i ${S_ETH} -p tcp -m tcp --dport ${S_VM_PORT_SSH_PRE}${CTID} -j DNAT --to-destination ${_VM_IP_BASE}.${CTID}:${S_SSH_PORT}"
		done

		_exit 0
	   ;;
	del)
		# no citd
		! [ "$*" ] && _exite "Missing ctids: '$*' for arguments '$OPTSGIVEN'"

		# rule exist
		CTIDRULEEXIST="$(iptables-save|grep "^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE[0-9]* .* " |sed "s/^.* PREROUTING .* --dport $S_VM_PORT_SSH_PRE\([0-9]*\) .*$/\1/"|sort -u|xargs)"
		if [ "$*" == "all" ]; then
			CTIDRULE="$CTIDRULEEXIST"
			CTIDNORULE=
		else
			CTIDRULE=
			CTIDLIST="$(_vz_ctids_clean "$* ")"
			for CTID in $CTIDLIST; do
				[ "${CTIDRULEEXIST/$CTID/}" != "$CTIDRULEEXIST" ] && CTIDRULE+="$CTID " || CTIDNORULE+="$CTID "
			done
		fi
		_echoD "$FUNCNAME:$LINENO CTIDRULE='$CTIDRULE' CTIDNORULE='$CTIDNORULE'"

		# stopped
		CTIDSSTOPPED="$(${VZLIST} -SHo ctid|xargs)"
		if [ "$ALL" ]; then
			CTIDSTOP="$CTIDRULE"
			CTIDNOSTOP=
		else
			for CTID in $CTIDRULE; do
				[ "${CTIDSSTOPPED/$CTID/}" != "$CTIDSSTOPPED" ] && CTIDSTOP+="$CTID " || CTIDNOSTOP+="$CTID "
			done
		fi
		_echoD "$FUNCNAME:$LINENO CTIDSTOP='$CTIDSTOP' CTIDNOSTOP='$CTIDNOSTOP'"

		# synthesis
		_echoD "$FUNCNAME:$LINENO CTIDRULE='$CTIDRULE' CTIDNORULE='$CTIDNORULE' CTIDSTOP='$CTIDSTOP' CTIDNOSTOP='$CTIDNOSTOP'"
		[ "$CTIDNORULE" ] && _echoW "Rules doesn't exist :      $CTIDNORULE"
		[ "$CTIDNOSTOP" ] && _echoW "Containers running :       $CTIDNOSTOP"

		 # confirm
		if [ "$CTIDSTOP" ]; then
			if [ ! "$CONFIRM" ]; then
				_echoW "Containers to $ACTION iptables rules : ${cclear}${blueb}$CTIDSTOP"
				_askyn "confirm ?" && [ "$_ANSWER" == "n" ] && _exit
			fi
		else
			_exit 0
		fi

		# execute
		for CTID in $CTIDSTOP;
		do
			while read line
			do
				if [ "$line" ]; then
					[ "$VIEW" ] && _echoT "delete iptables rule for $CTID"
					_eval "$IPT -D${line#-A}"
				fi
			done <<<"$(iptables-save|grep "^.* PREROUTING .*--dport $S_VM_PORT_SSH_PRE$CTID .* ")"
		done

		_exit 0
		;;
	* )
		_exite "Wrong action: '$ACTION' for arguments '$OPTSGIVEN'"
		;;
esac

_exit 0

