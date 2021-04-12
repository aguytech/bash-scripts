#!/bin/bash
#
# Provides:             vz-ctl
# Short-Description:    functions over vzctl to manipulate containers
# Description:          functions over vzctl to manipulate containers

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions.sh}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  FUNCTION

# confirmation
# $1 : command
# $2 : CTIDs
# $3 : options for command
__confirm() {
	[ "$#" != 3 ] && _exite "$FUNCNAME:$LINENO missing parameters: '$#'"
	_echoD "$FUNCNAME:$LINENO \$*=$*"

	_echoT "vz-ctl $1 $2"
	[ "$3" ] && _echoT "with options: $3"
	_askno "${whiteb}confirm ? y(n) ${cclear}"
	[ "$_ANSWER" != "y" ] && _exit 0
}

# excecute command
# $1 : action
# $2 : ctids
# $3 : options
# $4 : iptables action
__execute() {
	[ "$#" -lt 2 ] && _exite "$FUNCNAME:$LINENO missing parameters: '$#'"
	_echoD "$FUNCNAME:$LINENO \$*='$*'"

	for __CTID in $2
	do
		# destroy binded paths
		[ "${1##* }" == "destroy" ] && __umount "$__CTID"

		_echoT "$1 $__CTID"
		_eval "$1 $__CTID $3"

		# iptables
		if [ "$4" ]; then
			_eval "vz-iptables $4 -y$QUIET $__CTID"
		fi
	done
}

# delete node path for ctid
# $1 : __CTID
__umount() {
	for __CTID in $*; do
		_echoD "$FUNCNAME:$LINENO __CTID='$__CTID'"
		if [[ "$__CTID" =~ ^[0-9]*$ && $__CTID -ge $S_VM_CTID_MIN && $__CTID -le $S_VM_CTID_MAX ]]; then

			PATHSBIND="$(grep "^SRC=.*" "$S_VZ_PATH_CT_CONF/$__CTID.mount"|sed "s/^SRC=\(.*\)/\1/"|xargs)"
			_echoD "$FUNCNAME:$LINENO PATHSBIND='$PATHSBIND'"

			for PATHBIND in $PATHSBIND; do
				# delete directory
				[ -d "$PATHBIND" ] && _evalq rm -fR "$PATHBIND"
			done

		else
			_echoE "container are skipped, wrong ctid '$__CTID',  must be between $S_VM_CTID_MIN - $S_VM_CTID_MAX"
		fi
	done
}

__start() {
	USAGE="vz-ctl start : start containers
vz-ctl start [options] <ctids/all>
Mounts (if necessary) and starts a container. Unless --wait option is specified, vzctl will return immediately

options:
--help            get informations about usage
-y, --confirm     confirm action without prompt
-q, --quiet       don't show any infomations except interaction informations
-d, --debug       output in screen & in file debug informations

--force           if you want to start a container which is disabled (see --disabled)
--wait            otherwise an attempt to wait till the default runlevel is reached will be made by vzctl
--skip-fsck       skip fsck for ploop-based container filesystem (this option is used by vz initscript)
--skip-remount    skip remount filesystem
"

	CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
	CTIDSELECT="$(${VZLIST} -SHo ctid|xargs)"

	OPTSSHORT="hdqy"
	OPTSLONG="help,debug,quiet,confirm,force,wait,skip-fsck,skip-remount"
	OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- $OPTSGIVEN 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
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
			-q|--quiet)
				QUIET=q
				_redirect quiet
				;;
			-y|--confirm)
				CONFIRM=y
				;;
			--force|--wait|--skip-fsck|--skip-remount)
				OPTSLIST+=" --$1"
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
	OPTS="${*/$ACTION/}"; OPTS="${OPTS# }"
	_echoD "$FUNCNAME:$LINENO OPTSLIST='$OPTSLIST' CONFIRM='$CONFIRM' OPTS='$OPTS'"

	# list initialize
	[ "$OPTS" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$OPTS")"
	_echoD "$FUNCNAME:$LINENO CTIDLIST='$CTIDLIST'"

	# list empty
	[ ! "$CTIDLIST" ] && _echoE "No valid containers for your selection '$OPTS'" && _exit 0

	# define final list
	for CTID in $CTIDLIST; do
		if [ "$CTIDEXIST" != "${CTIDEXIST/$CTID/}" ]; then
			[ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ] && CTIDCMD+="$CTID " || CTIDNOACTION+="$CTID "
		else
			NOCTIDEXIST+="$CTID "
		fi
	done
	CTIDCMD=${CTIDCMD% }

	# synthesis
	#[ "$NOCTIDEXIST" ] && _echo "Containers does not exist : ${redb}$NOCTIDEXIST${cclear}"
	[ "$CTIDNOACTION" ] && _echo "Containers running : ${whiteb}$CTIDNOACTION${cclear}"

	# confirm
	[[ "$CTIDCMD" && ! "$CONFIRM" ]] && __confirm "$ACTION" "$CTIDCMD" "$OPTSLIST"

	# execute
	[ "$CTIDCMD" ] && __execute "${VZCTL} $ACTION" "$CTIDCMD"  "$OPTSLIST" add

}

__stop() {

	USAGE="vz-ctl stop : stop containers
vz-ctl stop [options] <ctids/all>
Stops a container and unmounts it (unless --skip-umount is given). Normally, halt(8) is executed inside a container; option --fast makes vzctl use reboot(2) syscall instead which is faster but can lead to unclean container shutdown. Default wait timeout is 120 seconds; it can be changed globally, by setting STOP_TIMEOUT in vz.conf(5), or per container (STOP_TIMEOUT in ctid.conf(5), see --stop-timeout)

options:
--help           get informations about usage
-y, --confirm    confirm action without prompt
-q, --quiet      don't show any infomations except interaction informations
-d, --debug      output in screen & in file debug informations

--fast           makes vzctl use reboot(2) syscall instead which is faster but can lead to unclean container shutdown
--skip-umount    skip umounts
"

	CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
	CTIDSELECT="$(${VZLIST} -Ho ctid 2>/dev/null|xargs)"

	OPTSSHORT="hdqy"
	OPTSLONG="help,debug,quiet,confirm,fast,skip-umount"
	OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- $OPTSGIVEN 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
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
			-q|--quiet)
				QUIET=q
				_redirect quiet
				;;
			-y|--confirm)
				CONFIRM=y
				;;
			--fast|--skip-umount)
				OPTSLIST+=" --$1" ;;
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
	OPTS="${*/$ACTION/}"; OPTS="${OPTS# }"
	_echoD "$FUNCNAME:$LINENO OPTSLIST='$OPTSLIST' CONFIRM='$CONFIRM' OPTS='$OPTS'"

	# list initialize
	[ "$OPTS" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$OPTS")"
	_echoD "$FUNCNAME:$LINENO CTIDLIST='$CTIDLIST'"

	# list empty
	[ ! "$CTIDLIST" ] && _echoE "No valid containers for your selection '$OPTS'" && _exit 0

	# define final list
	for CTID in $CTIDLIST; do
		if [ "$CTIDEXIST" != "${CTIDEXIST/$CTID/}" ]; then
			[ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ] && CTIDCMD+="$CTID " || CTIDNOACTION+="$CTID "
		else
			NOCTIDEXIST+="$CTID "
		fi
	done
	CTIDCMD=${CTIDCMD% }

	# synthesis
	#[ "$NOCTIDEXIST" ] && _echo "Containers does not exist : ${redb}$NOCTIDEXIST${cclear}"
	[ "$CTIDNOACTION" ] && _echo "Containers not running : ${whiteb}$CTIDNOACTION${cclear}"

	# confirm
	[[ "$CTIDCMD" && ! "$CONFIRM" ]] && __confirm "$ACTION" "$CTIDCMD" "$OPTSLIST"

	# execute
	[ "$CTIDCMD" ] && __execute "${VZCTL} $ACTION" "$CTIDCMD" "$OPTSLIST" del

}

__restart() {

	USAGE="vz-ctl restart : restart containers
vz-ctl restart [options] <ctids/all>
Mounts (if necessary) and starts a container. Unless --wait option is specified, vzctl will return immediately

options:
--help            get informations about usage
-y, --confirm     confirm action without prompt
-q, --quiet       don't show any infomations except interaction informations
-d, --debug       output in screen & in file debug informations

--fast            makes vzctl use reboot(2) syscall instead which is faster but can lead to unclean container shutdown
--skip-umount     skip umounts

--force           if you want to start a container which is disabled (see --disabled)
--wait            otherwise an attempt to wait till the default runlevel is reached will be made by vzctl
--skip-fsck       skip fsck for ploop-based container filesystem (this option is used by vz initscript)
--skip-remount    skip remount filesystem

	"

	CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
	CTIDSELECT="$(${VZLIST} -Ho ctid 2>/dev/null|xargs)"

	OPTSSHORT="hdqy"
	OPTSLONG="help,debug,quiet,confirm,fast,skip-umount,force,wait,skip-fsck,skip-remount"
	OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- $OPTSGIVEN 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
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
			-q|--quiet)
				QUIET=q
				_redirect quiet
				;;
			-y|--confirm)
				CONFIRM=y
				;;
			--fast|--skip-umount|--force|--wait|--skip-fsck|--skip-remount)
				OPTSLIST+=" --$1"
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
	OPTS="${*/$ACTION/}"; OPTS="${OPTS# }"
	_echoD "$FUNCNAME:$LINENO OPTSLIST='$OPTSLIST' CONFIRM='$CONFIRM' OPTS='$OPTS'"

	# list initialize
	[ "$OPTS" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$OPTS")"
	_echoD "$FUNCNAME:$LINENO CTIDLIST='$CTIDLIST'"

	# list empty
	[ ! "$CTIDLIST" ] && _exite "No valid containers for your selection '$OPTS'"

	# define final list
	for CTID in $CTIDLIST; do
		if [ "$CTIDEXIST" != "${CTIDEXIST/$CTID/}" ]; then
			[ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ] && CTIDCMD+="$CTID " || CTIDNOACTION+="$CTID "
		else
			NOCTIDEXIST+="$CTID "
		fi
	done
	CTIDCMD=${CTIDCMD% }

	# synthesis
	#[ "$NOCTIDEXIST" ] && _echo "Containers does not exist : ${redb}$NOCTIDEXIST${cclear}"
	[ "$CTIDNOACTION" ] && _echo "Containers not running : ${whiteb}$CTIDNOACTION${cclear}"

	# confirm
	[[ "$CTIDCMD" && ! "$CONFIRM" ]] && __confirm "$ACTION" "$CTIDCMD" "$OPTSLIST"

	# execute
	[ "$CTIDCMD" ] && __execute "${VZCTL} $ACTION" "$CTIDCMD" "$OPTSLIST"

}

__runscript()
{
	USAGE="vz-ctl script : run script in containers
vz-ctl runscript [options] [-s, --script] <script> <ctids/all>
Run specified shell script in the container. Argument script is a file on the host system which contents is read by vzctl
and executed in the context of the container. For a running container, the command jumps into the container and executes the script.
For a stopped container, it enters the container, mounts container’s root filesystem, executes the script, and unmounts CT root.
In the latter case, the container is not really started, no file systems other than root (such as /proc) are mounted,
no startup scripts are executed etc. Thus the environment in which the script is running is far from normal
and is only usable for very basic operations.

options:
--help           get informations about usage
-s, --script     script to run
-y, --confirm    confirm action without prompt
-q, --quiet      don't show any infomations except interaction informations
-d, --debug      output in screen & in file debug informations
"

	CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
	CTIDSELECT="$(${VZLIST} -SHo ctid|xargs)"

	OPTSSHORT="hdqs:"
	OPTSLONG="help,debug,quiet,script:"
	OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- $OPTSGIVEN 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
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
			-q|--quiet)
				QUIET=q
				_redirect quiet
				;;
			-s|--script)
				shift
				_SCRIPT="$1"
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
	OPTS="${*/$ACTION/}"; OPTS="${OPTS# }"
	_echoD "$FUNCNAME:$LINENO OPTSLIST='$OPTSLIST' CONFIRM='$CONFIRM' OPTS='$OPTS'"

	# script file
	_require $_SCRIPT

	# list initialize
	[ "$OPTS" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$OPTS")"
	_echoD "$FUNCNAME:$LINENO CTIDLIST='$CTIDLIST'"

	# list empty
	[ ! "$CTIDLIST" ] && _echoE "No valid containers for your selection '$OPTS'" && _exit 0

	# define final list
	for CTID in $CTIDLIST; do
		if [ "$CTIDEXIST" != "${CTIDEXIST/$CTID/}" ]; then
			[ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ] && CTIDCMD+="$CTID " || CTIDNOACTION+="$CTID "
		else
			NOCTIDEXIST+="$CTID "
		fi
	done
	CTIDCMD=${CTIDCMD% }

	# synthesis
	#[ "$NOCTIDEXIST" ] && _echo "Containers does not exist : ${redb}$NOCTIDEXIST${cclear}"
	[ "$CTIDNOACTION" ] && _echo "Containers not running : ${whiteb}$CTIDNOACTION${cclear}"

	# no container
	[ ! "$CTIDCMD" ] && _echo "no valid containers for your selection" && return 0

	# confirm
	[ ! "$CONFIRM" ] && __confirm "$ACTION" "$CTIDCMD" "$OPTSLIST"

	# execute
	__execute "${VZCTL} $ACTION" "$CTIDCMD" "$_SCRIPT"

}

__woopt()
{
	USAGE="vz-ctl destroy|mount|umount|status|compact|quotaon|quotaoff|quotainit <ctid>
actions:
vz-ctl destroy <ctid>      Removes a container private area by deleting all files, directories
            and the configuration file of this container.
vz-ctl mount <ctid>        Mounts container private area. Note that this command can lead to execution
            of premount and mount action scripts (see ACTION _SCRIPTS below).
vz-ctl umount <ctid>       Unmounts container private area. Note that this command can lead to execution
            of umount and postumount action scripts (see ACTION _SCRIPTS below).
vz-ctl status <ctid>       Shows a container status. This is a line with five or six words, separated by spaces.
vz-ctl compact <ctid>      Compact container image. This only makes sense for ploop layout.
vz-ctl quotaon <ctid>      Turn disk quota on. Not that mount and start does that automatically.
vz-ctl quotaoff <ctid>     Turn disk quota off. Not that umount and stop does that automatically.
vz-ctl quotainit <ctid>    Initialize disk quota (i.e. run vzquota init) with the parameters taken from the CT configuration file ctid.conf(5).

options:
--help           get informations about usage
-y, --confirm    confirm action without prompt
-q, --quiet      don't show any infomations except interaction informations
-d, --debug      output in screen & in file debug informations
"

	CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
	CTIDSELECT="$(${VZLIST} -SHo ctid|xargs)"

	OPTSSHORT="hdqy"
	OPTSLONG="help,debug,quiet,confirm"
	OPTS=$(getopt -o $OPTSSHORT -l $OPTSLONG -n "${0##*/}" -- $OPTSGIVEN 2>/tmp/${0##*/}) || _exite "wrong options '$(</tmp/${0##*/})'"
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
			-q|--quiet)
				QUIET=q
				_redirect quiet
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
	OPTS="${*/$ACTION/}"; OPTS="${OPTS# }"
	_echoD "$FUNCNAME:$LINENO OPTSLIST='$OPTSLIST' CONFIRM='$CONFIRM' OPTS='$OPTS'"


	# list initialize
	[ "$OPTS" == "all" ] && CTIDLIST="$CTIDSELECT" || CTIDLIST="$(_vz_ctids_clean "$OPTS")"
	_echoD "$FUNCNAME:$LINENO CTIDLIST='$CTIDLIST'"

	# list empty
	[ ! "$CTIDLIST" ] && _exite "No valid containers for your selection '$OPTS'"

	# define final list
	for CTID in $CTIDLIST; do
		if [ "$CTIDEXIST" != "${CTIDEXIST/$CTID/}" ]; then
			[ "$CTIDSELECT" != "${CTIDSELECT/$CTID/}" ] && CTIDCMD+="$CTID " || CTIDNOACTION+="$CTID "
		else
			NOCTIDEXIST+="$CTID "
		fi
	done
	CTIDCMD=${CTIDCMD% }

	# synthesis
	#[ "$NOCTIDEXIST" ] && _echo "Containers does not exist : ${redb}$NOCTIDEXIST${cclear}"
	[ "$CTIDNOACTION" ] && _echo "Containers running : ${whiteb}$CTIDNOACTION${cclear}"

	# no container
	[ ! "$CTIDCMD" ] && _echo "no valid containers for your selection" && return 0

	# confirm
	[[ "$CTIDCMD" && ! "$CONFIRM" ]] && __confirm "$ACTION" "$CTIDCMD" "$OPTSLIST"

	_echoD "$FUNCNAME:$LINENO ACTION='$ACTION' CTID='$CTID'"
	_evalq "__execute '${VZCTL} $ACTION' '$CTIDCMD'"
}

################################  VARIABLES

USAGE="vz-ctl : manage containers, selection is made only with stopping containers (use -a,all for all containers)
Usage: vz-ctl [options] <command> <ctid> [parameters]

vz-ctl create [options] <ctid>
    [--ostemplate <name>] [--config <name>] [--layout ploop|simfs]
    [--hostname <name>] [--name <name>] [--ipadd <addr>] [--diskspace <kbytes>]
    [--diskinodes <NUM> [--private <path>] [--root <path>] [--local_uid <UID>]
    [--local_gid <GID>]
vz-ctl start [options] <ctid>
    [--force] [--wait] [--skip-fsck] [--skip-remount]
vz-ctl stop [options] <ctid>
    [ --skip-umount] [--fast]
vz-ctl restart [options] <ctid>
    [--force] [--wait] [--skip-fsck] [--skip-remount] [ --skip-umount] [--fast]
vz-ctl destroy | mount | umount | status <ctid>
vz-ctl quotaon | quotaoff | quotainit <ctid>
vz-ctl runscript <script> <ctid>
vz-ctl set  [options] <ctid>
    [--save] [--force] [--setmode restart|ignore]
    [--ram <bytes>[KMG]] [--swap <bytes>[KMG]]
    [--ipadd <addr>] [--ipdel <addr>|all] [--hostname <name>]
    [--nameserver <addr>] [--searchdomain <name>]
    [--onboot yes|no] [--bootorder <N>]
    [--userpasswd <user>:<passwd>]
    [--cpuunits <N>] [--cpulimit <N>] [--cpus <N>]
    [--cpumask <cpus>] [--nodemask <nodes>]
    [--diskspace <soft>[:<hard>]] [--diskinodes <soft>[:<hard>]]
    [--quotatime <N>] [--quotaugidlimit <N>] [--mount_opts <opt>[,<opt>...]]
    [--offline-resize] [--capability <name>:on|off ...]
    [--devices b|c:major:minor|all:r|w|rw]
    [--devnodes device:r|w|rw|none]
    [--netif_add <ifname[,mac,host_ifname,host_mac,bridge]]>]
    [--netif_del <ifname>]
    [--applyconfig <name>] [--applyconfig_map <name>]
    [--features <name:on|off>] [--name <vename>]
    [--ioprio <N>] [--iolimit <N>] [--iopslimit <N>]
    [--pci_add [<domain>:]<bus>:<slot>.<func>] [--pci_del <d:b:s.f>]
    [--iptables <name>] [--disabled <yes|no>]
    [--stop-timeout <seconds>
    [UBC parameters]

UBC parameters (N - items, P - pages, B - bytes):
Two numbers divided by colon means barrier:limit.
In case the limit is not given it is set to the same value as the barrier.
   --numproc N[:N]      --numtcpsock N[:N]    --numothersock N[:N]
   --vmguarpages P[:P]  --kmemsize B[:B]      --tcpsndbuf B[:B]
   --tcprcvbuf B[:B]    --othersockbuf B[:B]  --dgramrcvbuf B[:B]
   --oomguarpages P[:P] --lockedpages P[:P]   --privvmpages P[:P]
   --shmpages P[:P]     --numfile N[:N]       --numflock N[:N]
   --numpty N[:N]       --numsiginfo N[:N]    --dcachesize N[:N]
   --numiptent N[:N]    --physpages P[:P]     --avnumproc N[:N]
   --swappages P[:P]
"

################################  MAIN

# openvz server
type vzctl &>/dev/null && VZCTL="vzctl" || VZCTL="/usr/sbin/vzctl"
type ${VZCTL} &>/dev/null || _exite "unable to find vzctl command"

# openvz server
type vzlist &>/dev/null && VZLIST="vzlist" || VZLIST="/usr/sbin/vzlist"
type ${VZLIST} &>/dev/null || _exite "unable to find vzlist command"

_echoD "$FUNCNAME:$LINENO $_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"


OPTSGIVEN="$@"
_echoD "$FUNCNAME:$LINENO OPTSGIVEN='$OPTSGIVEN'"

# help
[ "${*/--help/}" != "$*" ] && _echo "$USAGE" && _exit

# select an action
for STR in restart create start stop runscript; do
	if [ "${*/$STR/}" != "$*" ]; then ACTION=$STR; CMD="__$STR"; break; fi
done
_echoD "$FUNCNAME:$LINENO ACTION='$ACTION' CMD='$CMD' OPTSGIVEN='$OPTSGIVEN'"
if [ ! "$ACTION" ]; then
	for STR in destroy mount umount status compact quotaon quotaoff quotainit; do
		if [ "${*/$STR/}" != "$*" ]; then ACTION=$STR; CMD="__woopt"; break; fi
	done
fi
_echoD "$FUNCNAME:$LINENO ACTION='$ACTION' CMD='$CMD' OPTSGIVEN='$OPTSGIVEN'"


#################  ACTION

# no good action found
[ ! "$ACTION" ] && _exite "unable to find a good action to do in '$OPTSGIVEN'"

# source action script file
#_source "$_PATH_BASE/inc-$_SCRIPT-$SOURCE"

$CMD

_exit 0

<<KEEP
# create mount log
# $1 : __CTID
__mount() {
	__CTID=$@
	_echoD "$FUNCNAME:$LINENO __CTID='$__CTID'"
	! [ "$__CTID" ] && _exite "Missing ctid for calling '$0 $*'"
	if ! [[ "$__CTID" =~ ^[0-9]*$ && $__CTID -ge $S_VM_CTID_MIN && $__CTID -le $S_VM_CTID_MAX ]]; then
		_exite "Wrong '$__CTID' must be between $S_VM_CTID_MIN - $S_VM_CTID_MAX"
	fi

	PATHLOG="$S_VZ_PATH_NODE/$__CTID/log"
	FILEMOUNT="/etc/vz/conf/${__CTID}.mount"
	_echoD "$FUNCNAME:$LINENO FILEMOUNT='$FILEMOUNT' PATHLOG='$PATHLOG'"

	# create directory
	[ -d $PATHLOG ] && rm -fR $PATHLOG
	mkdir -p $PATHLOG

	echo '#!/bin/bash
# mount device for '$__CTID'

# log
. /etc/vz/vz.conf
. ${VE_CONFFILE}
SRC='$PATHLOG'
DST="$S_PATH_LOG"
! [ -p ${VE_ROOT}${DST} ] && mkdir -p ${VE_ROOT}${DST}
mount -n --bind ${SRC} ${VE_ROOT}${DST}
' > /etc/vz/conf/${__CTID}.mount
	chmod +x /etc/vz/conf/${__CTID}.mount
}
KEEP

