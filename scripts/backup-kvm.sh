#!/bin/bash
#
# Provides:             backup-kvm
# Short-Description:    backup kvm configuration, image & exports
# Description:          backup kvm configuration, image & exports

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions.sh}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  VARIABLES

USAGE="backup-kvm : backup kvm configuration, image & exports. By default save all, use options for a selected save
backup-kvm --help

options:
    -c, --conf      save only kvm configuration files
    -e, --export    save only kvm exports
    -i, --image     save only kvm images
    -q, --quiet     don't show any infomations except interaction informations
    --debug         output in screen & in file debug informations
"


################################################################  _SCRIPT

# compress path
# $1 path base
# $2 sub path
__compress() {
	PATHFROM="$1"
	PATHSUBS="$2"
	PATH2="${PATHFROM#/}"; PATH2="$PATHSAVE/${PATH2//\//.}"; PATH2="${PATH2%/}"
	_echoD "$FUNCNAME:$LINENO PATHFROM='$PATHFROM' PATHSUBS='$PATHSUBS' PATH2='$PATH2'"

	# wrong path
	! [ -d "$PATHFROM" ] && _exite "Wrong path '$PATHFROM' for calling '$*'"

	# create path
	! [ -d "$PATH2" ] && mkdir -p "$PATH2"

	cd "$PATHFROM"
	_echoT "$PWD"

	PATHSUBS=$(echo "$PATHSUBS")

	for PATHSUB in $PATHSUBS
	do
		if [ -d "$PATHSUB" ]; then
			FILE2="${PATHSUB#/}"
			FILE2="${FILE2//\//.}"
			FILE2="$PATH2/${FILE2%/}.$CMPEXT"

			_echo "compress $PATHSUB"
			_evalq "tar $CMPOPT $FILE2 $PATHSUB"
		else
			_echoE "wrong path '$PATHSUB'"
			_echoD "$FUNCNAME:$LINENO ERROR| Wrong path '$PATHSUB'"
		fi
	done
}

# synchronize files
# $1 path base
# $2 sub path
# $3 exclude path
__sync() {
	PATHFROM="$1"
	PATHSUBS="$2"
	EXCLUDES="lost+found $3"
	PATH2="${PATHFROM#/}"; PATH2="$PATHSAVE/${PATH2//\//.}"; PATH2="${PATH2%/}"
	_echoD "$FUNCNAME:$LINENO PATHFROM='$PATHFROM' PATHSUBS='$PATHSUBS' PATH2='$PATH2'"

	# wrong path
	! [ -d "$PATHFROM" ] && _exite "Wrong path '$PATHFROM' for calling '$*'"

	# create path
	! [ -d "$PATH2" ] && mkdir -p "$PATH2"

	cd "$PATH2"
	_echoT "$PWD"

	for PATHSUB in $PATHSUBS
	do
		if [ -d "$PATHFROM/$PATHSUB" ]; then
			PATHSUB2="${PATH2}/${PATHSUB#/}"
			! [ -d "$PATHSUB2" ] && mkdir -p "$PATHSUB2"

			STR=; for exclude in $EXCLUDES; do STR+=" --exclude='$exclude'"; done
			_echo "sync $PATHSUB"
			_evalq "rsync -a $STR $PATHFROM/$PATHSUB/ $PATHSUB2/"
		else
			_echoE "wrong path '$PATHFROM/$PATHSUB'"
			_echoD "$FUNCNAME:$LINENO ERROR| Wrong path '$PATHFROM/$PATHSUB'"
		fi
	done
}
tat=`ls ter/rzer|grep t|sort`
tot=$(fdfdfdfdfdf)
<<KEEP
dfsdgfsdfsd
fds
fds
fdf
KEEP
while read $LINE; do echo $LINE; done <<< "$"

################################  MAIN

_echoD "$FUNCNAME:$LINENO $_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"

DATE="$(date "+%Y%m%d")"
PATHSAVE="$S_PATH_SAVE_BACKUP/$DATE"

OPTSGIVEN="$@"
OPTSSHORT="dceiq"
OPTSLONG="help,debug,conf,export,image,quiet"
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
		-c|--conf)
			CONF=c
			;;
		-e|--export)
			ALL=
			EXPORT=e
			;;
		-i|--image)
			ALL=
			IMAGE=i
			;;
		-q|--quiet)
			_redirect quiet
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

# all options
if ! [ "$OPTSGIVEN" ]; then CONF=c; EXPORT=e; IMAGE=i; fi
_echoD "$FUNCNAME:$LINENO CONF='$CONF' EXPORT='$EXPORT' IMAGE='$IMAGE'"

# conf
if [[ "$CONF" || "$ALL" ]]; then
	PATHFROM="/"
	PATHSUBS="etc/libvirt"
	__compress "$PATHFROM" "$PATHSUBS"
fi

# image
if [[ "$IMAGE" || "$ALL" ]]; then
	PATHFROM="/var/lib/libvirt"
	PATHSUBS="image"
	__compress "$PATHFROM" "$PATHSUBS"
fi

# export
if [[ "$EXPORT" || "$ALL" ]]; then
	PATHFROM="/var/lib/libvirt"
	PATHSUBS="export"
	__compress "$PATHFROM" "$PATHSUBS"
fi

_exit 0
