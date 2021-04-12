#!/bin/bash
#
# Provides:             vz-clean
# Short-Description:    functions to clean the dumping containers
# Description:          functions to clean the dumping containers

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1

################################  VARIABLES

USAGE="vz-clean, functions to clean the dumping containers. by default search in all container (see [--search-name]).
vz-clean --help

vz-clean [options] [--search-name <pattern>] [<ctids/all>]
    ctids is a list combinating simple ids of containers and range. ex: '100 200-210'

options:
    -p, --process    process cleaning without confirmation, be carefull !
    -y, --confirm    confirm action without prompt
    -q, --quiet      don't show any infomations except interaction informations
    -d, --debug      output in screen & in file debug informations
    -l, --list       list available dumps
    -s, --sort col   sort by number of followings columns: size, ctid, hostname, date, filetype. ONLY for listing
    -a, --auto       preselect dumps by his hostname which have more than 1 date files

    t, --template    restore dumping files for template in S_VZ_PATH_DUMP_TEMPLATE

    -h, --search-hname <>    search containers whith a part of hostname of containers
    -r, --search-regexp <>   search containers whith a regexp pattern of hostname of containers
"


################################  FUNCTION


################################  MAIN

# openvz server
type vzlist &>/dev/null && VZLIST="vzlist" || VZLIST="/usr/sbin/vzlist"
type ${VZLIST} &>/dev/null || _exite "unable to find vzlist command"

_echoD "$FUNCNAME:$LINENO $_SCRIPT / $(date +"%d-%m-%Y %T : %N") ---- start"

SORTSTR="-k3,3 -k4,4r"
CTIDEXIST="$(${VZLIST} -aHo ctid|xargs)"
PATHDUMP="$S_VZ_PATH_DUMP"
PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"

OPTSGIVEN="$@"
OPTSSHORT="dalpqtyh:r:s:"
OPTSLONG="help,debug,auto,list,process,quiet,template,confirm,search-hname:,search-regexp:,sort:"
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
		-a|--auto)
			AUTO=auto
			;;
		-l|--list)
			LIST=l
			;;
		-p|--process)
			PROCESS=p
			CONFIRM=y
			;;
		-q|--quiet)
			_redirect quiet
			;;
		-t|--template)
			PATHDUMP="$S_VZ_PATH_DUMP_TEMPLATE"
			PATHDUMPXTRA="$PATHDUMP/$S_PATH_VZ_DUMP_REL_XTRA"
			;;
		-y|--confirm)
			CONFIRM=y
			;;
		-h|--search-hname)
			shift
			[ ! "$1" ] && _exite "Missing arguments for option '$1' in '$OPTSGIVEN'"
			SEARCH=hname
			SEARCHSTR=$1
			;;
		-r|--search-regexp)
			shift
			[ ! "$1" ] && _exite "Missing arguments for option '$1' in '$OPTSGIVEN'"
			SEARCH=regexp
			SEARCHSTR=$1
			;;
		-s|--sort)
			shift
			[ ! "$1" ] && _exite "Missing arguments for option '$1' in '$OPTSGIVEN'"
			SORT="$1"
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
_echoD "$FUNCNAME:$LINENO PATHDUMP='$PATHDUMP' PATHDUMPXTRA='$PATHDUMPXTRA'"
_echoD "$FUNCNAME:$LINENO SEARCH='$SEARCH' SEARCHSTR='$SEARCHSTR' SORT='$SORT' LIST='$LIST'"

# no value for containers
#[[ ! "$*" && ! "$LIST" ]] && _exite "Missing arguments for ctids '$*' for your call '$OPTSGIVEN'"

################  SORT

if [ "$SORT" ]; then
	[[ "$SORT" =~ ^-.*$ ]] && SORTSTR="r" && SORT=${SORT#-} || SORTSTR=
	! [[ "$SORT" =~ [12345] ]] && _exite "Wrong option for sorting: '$SORT' for your call '$OPTSGIVEN'"
	SORTSTR="-k$SORT,$SORT$SORTSTR"
fi
_echoD "$FUNCNAME:$LINENO SORTSTR='$SORTSTR'"

################  SELECT

# DUMPFOUND
case "$SEARCH" in
	hname)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_[0-9]*_.*${SEARCHSTR}.*_[0-9-]*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
	regexp)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_[0-9]*_${SEARCHSTR}_[0-9-]*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
	*)
		DUMPFOUND=$(ls -st $PATHDUMP|grep "vzdump_.*\.\(tgz\|tar\)"|tr " " "_"|sed s"/^_*\([0-9]\+.*\)$/\1/"|tr "." "_"|xargs)
		;;
esac
# order DUMPFOUND
DUMPFOUND=$(echo $DUMPFOUND|tr " " "\n"|tr "_" " "|sort -k4,4 -k5,5r|tr " " "_"|xargs)
_echoD "$FUNCNAME:$LINENO DUMPFOUND='$DUMPFOUND'"

# CTIDSELECT
[ "$*" ] && CTIDSELECT="$*" || CTIDSELECT="all"

if [ "$CTIDSELECT" != "all" ]; then
	CTIDSELECT="$(_vz_ctids_clean "$CTIDSELECT")"

	# minus DUMPFOUND by CTIDSELECT
	for DUMP in $DUMPFOUND; do
		CTID=$(echo $DUMP|awk -F "_" '{print $2}')
		[ "${CTIDSELECT/$CTID/}" != "$CTIDSELECT" ] && DUMPSELECT+="$DUMP "
	done
else
	DUMPSELECT=$DUMPFOUND
fi

_echoD "$FUNCNAME:$LINENO CTIDSELECT='$CTIDSELECT'\n DUMPSELECT='$DUMPSELECT'"


################ no DUMPSELECT

! [ "$DUMPSELECT" ] && _exite "No containers for your selection '$OPTSGIVEN'"


################  LIST

if [ "$LIST" ]; then
	echo $DUMPSELECT|tr " " "\n"|awk -F "_" '{ print $1 " " $3 " " $4 " " $5 " " $6}'|sort $SORTSTR|column -t >&5
	_exit 0
fi


################  MENU

if ! [ "$LIST" ]; then
	declare -A CLEANMENU
	declare -A CLEAN2DUMP

	# automated select duplicated hostname
	if [ "$AUTO" ]; then
		i=1
		SELECTTMP=
		for DUMP in $DUMPSELECT; do
			HOSTNAMECT=$(echo $DUMP|awk -F "_" '{print $4}')
			[ "$HOSTNAMECT" == "$SELECTTMP" ] && CLEAN2DUMP[$i]="$DUMP"
			SELECTTMP=$HOSTNAMECT
			let i++
		done
	fi

	# selection
	_ANSWER=$PROCESS
	while ! [[ "$_ANSWER" =~ ^q|p$ ]]; do

		# list of dumps selected & available for menu
		MENU=
		i=1
		for DUMP in $DUMPSELECT; do
			CLEANMENU[$i]="$DUMP"
			[ "${CLEAN2DUMP[$i]}" ] && selectpre="${blueb}" || selectpre="${white}"
			MENU+="${selectpre}$i)\t$(echo $DUMP|awk -F "_" '{ print $1 " " $3 " " $4 " " $5 " " $6 }')${cclear}\n"
			let i++
		done
		_echoD "$FUNCNAME:$LINENO CLEANMENU='${!CLEANMENU[*]}'"
		_echoD "$FUNCNAME:$LINENO MENU='${MENU}'"

		# menu
		_echo "---------------------------------------------------------"
		_echo "$(echo -e $MENU|column -t)"
		_echo "---------------------------------------------------------"
		_echo "ctids mounted: $CTIDEXIST"
		_echo "---------------------------------------------------------"

		_ask "Enter your selection (q: quit / p: process)"
		_echoD "$FUNCNAME:$LINENO selects='$_ANSWER' i='$i'"

		# quit
		[ "$_ANSWER" == "q" ] && _exit

		# not process
		if [ "$_ANSWER" != "p" ]; then
			for select in $_ANSWER; do
				if [[ 0 -lt $select && $select -lt $i ]]; then
					if [ "${CLEAN2DUMP[$select]+_}" ]; then unset CLEAN2DUMP[$select]
					else CLEAN2DUMP[$select]="${CLEANMENU[$select]}"
					fi
				else
					_echoE "wrong selection '$select', '$select' doesn't exists"
				fi
			done
			_echoD "$FUNCNAME:$LINENO CLEAN2DUMP keys=${!CLEAN2DUMP[*]} values=${CLEAN2DUMP[*]}"
		fi
	done

fi
_echoD "$FUNCNAME:$LINENO CLEAN2DUMP keys=${!CLEAN2DUMP[*]} values=${CLEAN2DUMP[*]}"


################ dump files

COUNT=0
SELECTSHOW=
for id in ${!CLEAN2DUMP[*]}
do
	SEARCHSTR="$(echo ${CLEAN2DUMP[$id]}|awk -F "_" '{ print $3 "_" $4 "_" $5 }')"
	while read LINE
	do
		if [ "$LINE" ]; then
			#_echoD "$FUNCNAME:$LINENO LINE='$LINE'"
			SELECTSHOW+="$LINE\n"
			let COUNT++
		fi
	done <<< "$(find $PATHDUMP -name "*$SEARCHSTR*")"
done
_echoD "$FUNCNAME:$LINENO SELECTSHOW='$SELECTSHOW'"


################  CONFIRM

if [ "$SELECTSHOW" ]; then
	_echoT "$(echo -e $SELECTSHOW|sed "s|$PATHDUMP||"|sort -n|column -t)"
	if [ ! "$CONFIRM" ]; then
		_askno "${whiteb}$COUNT file(s) to delete in '$PATHDUMP' ? y(n) ${cclear}"
		[ "$_ANSWER" != "y" ] && _exit 0
	fi
fi


################  COMMANDS

for FILE in $(echo -e $SELECTSHOW|tr "\n" " "); do
	# delete files
	_evalq "rm \"$FILE\""
done
_echoT "$COUNT files deleted"

_exit 0
