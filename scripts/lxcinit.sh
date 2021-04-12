#!/bin/bash
#
# Provides:						lxcinit
# Short-Description:		command to initalize container with options like apache, php-conf, mariadb
# Description:					command to initalize container with options like apache, php-conf, mariadb

################################ GLOBAL FUNCTIONS
#S_TRACE=debug

S_GLOBAL_FUNCTIONS="${S_GLOBAL_FUNCTIONS:-/usr/local/bs/inc-functions.sh}"
! . "$S_GLOBAL_FUNCTIONS" && echo -e "[error] - Unable to source file '$S_GLOBAL_FUNCTIONS' from '${BASH_SOURCE[0]}'" && exit 1
! . "$S_PATH_SCRIPT/inc-lxc.sh" && echo -e "[error] - Unable to source file '$S_PATH_SCRIPT/inc-lxc.sh' from '${BASH_SOURCE[0]}'" && exit 1

################################  VARIABLES

usage="lxcinit : initialize containers
the container name can be one or few name (separate with space)
and a special name 'all' to select all containers

Usage:    lxcinit <args> [image] [containers]

args:
	--mariadb		install mariadb
	--php				install php with apache

	-h, --help        show usage of functions
	-q, --quiet       don't show any infomations except interaction informations
	-d, --debug     output in screen & in file debug informations

Init usage:    lxcx init <options> [image] [containers]
		Initialize a container from an image for a name
"

################################  FUNCTION

__common() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"
	_echoD "${FUNCNAME}():$LINENO S_PATH_INSTALL=${S_PATH_INSTALL} S_PATH_SCRIPT=${S_PATH_SCRIPT}"

	# start the container if needed
	__lxc_is_stopped "$CTNAME" && lxc start "$CTNAME"

	# create path
	for path in "${GLOBAL_CONF}" "${S_PATH_SCRIPT}"; do
		_eval "lxc exec ${CTNAME} -- sh -c \"[ -d '$path' ] || mkdir -p '$path'\""
	done

	_eval lxc file push "${S_PATH_INSTALL_CONF}/server.conf" "${CTNAME}${GLOBAL_CONF}/"
	_eval lxc file push "${S_PATH_INSTALL_CONF}/env.conf" "${CTNAME}${GLOBAL_CONF}/"
}

__alpine312() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	local PATH_PROFILE="/etc/profile.d"

	# conf
	_eval lxc file push "${S_PATH_INSTALL_CONF}/bash-lxc-alpine.sh" "${CTNAME}${PATH_PROFILE}/"
	_eval lxc file push "${S_PATH_SCRIPT_CONF}/.bash_aliases" "${CTNAME}${PATH_PROFILE}/bash_aliases.sh"

	# common
	#mv /etc/profile.d/color_prompt /etc/profile.d/color_prompt.sh
	__lxc_exec 'apk update && apk upgrade
	apk add tzdata
	cp -a /usr/share/zoneinfo/Europe/Paris /etc/localtime
	echo "Europe/Paris" >  /etc/timezone
	apk del --purge tzdata'
}

__buster() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	# conf
	lxc file push "${S_PATH_INSTALL_CONF}/.bashrc-lxc-debian" "${CTNAME}/root/.bashrc"
	lxc file push "${S_PATH_SCRIPT_CONF}/.bash_aliases" "${CTNAME}/root/"
	lxc file push "${S_PATH_SCRIPT_CONF}/.vimrc" "${CTNAME}/root/"
	lxc file push "${S_PATH_INSTALL_CONF}/vim"/* "${CTNAME}/usr/share/vim/vim81/colors/"

	# common
	__lxc_exec 'apt update && apt dist-upgrade
	apt install -y bash-completion bsdmainutils less rsync openssh-server # cron htop logrotate man'

}

__focal() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

}

__alpine312_apache() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	local profile path

	# profile www
	profile="www"
	path="/home/shared/dev/eclipse-php-workspaces/lxc/www"
	# profile exists
	if __lxc_profile_exist "${profile}"; then
		 _echoD "profile '${CTNAME}' already exists"
	else
		_eval [ -d "${path}" ] || mkdir -p "${path}"
		_eval sudo setfacl -Rm u:100000:rwx "${path}"
		_eval sudo setfacl -Rm d:u:100000:rwx "${path}"
		_eval lxc profile create "${profile}"
		_eval lxc profile device add ${profile} localhost disk source=${path} path=/var/www/localhost
	fi
	# add to container profile
	if __lxc_has_profile "${CTNAME}" "${profile}"; then
		 _echoD "'${CTNAME}' has profile '${profile}'"
	else
		_eval lxc profile add "${CTNAME}" "${profile}"
	fi

	# install
	__lxc_exec 'apk add apache2
	rc-update add apache2 default'

	# config
	__lxc_exec 'path="/etc/apache2/httpd.conf"
	sed -i "s|^#ServerName.*|ServerName ambau.ovh:80|" "${path}"
	sed -i "s|^\(\s*DirectoryIndex index.html\).*|\1 index.php|" "${path}"
	sed -i "/^LoadModule mpm_prefork_module/ s|^|#|" "${path}"
	sed -i "/^#LoadModule mpm_event_module/ s|^#||" "${path}"
	rc-service apache2 start'
}

__alpine312_php() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	# apache
	__alpine312_apache

	# install
	__lxc_exec 'apk add apache2-proxy php7-fpm php7-pdo_mysql
	rc-update add php-fpm7 default'

	# config
	__lxc_exec 'path="/var/www/localhost/htdocs"
	ln -sv /usr/sbin/php-fpm7 /usr/bin/php
	echo "<?php phpinfo(); ?>" > "${path}/phpinf.php"
	echo "ProxyPassMatch ^/(.*\.php(/.*)?)\$ fcgi://127.0.0.1:9000${path}/\$1
ProxyTimeout 300
ProxyPassMatch ^/(fpm-ping|fpm-status) fcgi://127.0.0.1:9000
" >> /etc/apache2/httpd.conf

	mv "${path}/index.html" "${path}/index.html.keep"
	rc-service apache2 restart
	rc-service php-fpm7 start'

	# opcache
	__lxc_exec 'apk add php7-opcache
	rc-service php-fpm7 restart'

	# xdebug
	__lxc_exec 'paths="/home/shared/dev/eclipse-php-workspaces/lxc/www/xdebug/profile /home/shared/dev/eclipse-php-workspaces/lxc/www/xdebug/trace"
	for path in ${paths}; do
		[ -d "${path}" ] || mkdir -p "${path}"
	done
	apk add php7-pecl-xdebug'
	#xdebug conf
	lxc file push "${S_PATH_INSTALL_CONF}/php/xdebug.ini" "${CTNAME}/etc/php7/conf.d/"
	lxc file push "${S_PATH_SCRIPT}/php-switch" "${CTNAME}/${S_PATH_SCRIPT}/"
	__lxc_exec 'path="/etc/php7/conf.d/xdebug.ini"
sed -i "/;zend_extension/ s|^;||" "${path}"
sch="xdebug.profiler_output_dir"; str="/var/www/localhost/xdebug/profile"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.trace_output_dir"; str="/var/www/localhost/xdebug/trace"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.profiler_enable"; str="0"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.auto_trace"; str="0"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"

# autostart from outside
sch="xdebug.remote_autostart"; str="0"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.remote_enable"; str="1"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.remote_host"; str="10.0.0.1"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"
sch="xdebug.remote_log"; str="/var/log/apache2/xdebug.log"; sed -i "s|^.\?\($sch\s*=\).*|\1 $str|" "$path"

rc-service apache2 restart && rc-service php-fpm7 restart'
}

__alpine312_mariadb() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	# profile sgbd
	profile="sgbd"
	path=/home/shared/sgbd
	# profile exists
	if __lxc_profile_exist "${profile}"; then
		 _echoD "profile '${CTNAME}' already exists"
	else
		_eval [ -d "${path}" ] || mkdir -p "${path}"
		_eval sudo setfacl -Rm u:100000:rwx "${path}"
		_eval sudo setfacl -Rm d:u:100000:rwx "${path}"
		_eval lxc profile create "${profile}"
		_eval lxc profile device add ${profile} localhost disk source=${path} path=/var/share/sgbd
	fi
	# add to container profile
	if __lxc_has_profile "${CTNAME}" "${profile}"; then
		 _echoD "'${CTNAME}' has profile '${profile}'"
	else
		_eval lxc profile add "${CTNAME}" "${profile}"
	fi

	# install
	__lxc_exec 'apk add mariadb mariadb-client
	rc-update add mariadb default
	path="/etc/my.cnf.d/mariadb-server.cnf"
	sed -i "/^skip-networking/ s|^|#|" "$path"
	sed -i "/^#bind-address/ s|^#||" "$path"'

	# instance
	__lxc_exec '/etc/init.d/mariadb setup
	rc-service mariadb start'
	# interactive shell for mysql_secure_installation
	lxc exec ${CTNAME} -- mysql_secure_installation
}

__check() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	# method for image
	! test "$(declare -F | grep "f __${IMAGE}$")" && _exite "Unable to find method '__${IMAGE}'"

	# method for association image / configuration
	for conf in $confs; do
		! test "$(declare -F | grep "f __${IMAGE}_${conf}$")" && _exite "Unable to find method for options '${IMAGE}' & '${conf}'"
	done

	# image exists
	! __lxc_image_exist "${IMAGE}" && _exite "Unable to find image: '${IMAGE}'"

	# container name already exists
	__lxc_exist "${CTNAME}" && _exite "Container already exists: '${CTNAME}'"
}

__opts() {
	_echoD "${FUNCNAME}():$LINENO IN \$@=$@"

	opts_given="$@"
	opts_short="hqd"
	opts_long="mariadb,php,help,quiet,debug"
	opts=$(getopt -o ${opts_short} -l ${opts_long} -n "${0##*/}" -- "$@") || _exite "Wrong or missing options"
	eval set -- "${opts}"

	_echoD "${FUNCNAME}():$LINENO opts_given=$opts_given opts=$opts"
	while [ "$1" != "--" ]
	do
		case "$1" in
			--php)
				confs="${confs} php"
				;;
			--mariadb)
				confs="${confs} mariadb"
				;;
			--help)
				echo "$usage"
				;;
			--help)
				echo "$usage"
				;;
			-q|--quiet)
				_redirect quiet
				;;
			-d|--debug)
				_redirect debug
				;;
			*)
				_exite "Wrong argument: '$1' for arguments '$opts_given'"
				;;
		esac
		shift
	done

	shift
	# select image
	[ -z "$1" ] && _exite "You have to give an image to initialize container"
	IMAGE="$1"
	IMAGE="${IMAGE/debian10/buster}"
	IMAGE="${IMAGE/ubuntu2004/focal}"
	_echoD "${FUNCNAME}():$LINENO IMAGE='$IMAGE'"

	shift
	# no container name given
	[ -z "$1" ] && _exite "You have to give a container name to initialize it"
	CTNAME="$1"
	_echoD "${FUNCNAME}():$LINENO CTNAME='$CTNAME'"
}

__main() {
	_echod "======================================================"
	_echod "$(ps -o args= $PPID)"

	local opts_given opts_short opts_long opts confs conf
	local  IMAGE CTNAME

	# define global variables
	local GLOBAL_CONF="/etc/server"
	local S_PATH_INSTALL="/home/shared/dev/install"
	local S_PATH_INSTALL_CONF="${S_PATH_INSTALL}/conf"
	local S_PATH_SCRIPT="/usr/local/bs"
	local S_PATH_SCRIPT_CONF="${S_PATH_SCRIPT}/conf"

	# get options
	__opts "$@"

	# check method are implemented
	__check

	# init container
	lxc init ${IMAGE} ${CTNAME}
	lxc start ${CTNAME}
	#sleep 1
 	! __lxc_is_runnig ${CTNAME} && _exite "Something wrongs, container has no started"

	# common actions
	__common

	# call specific actions
	__${IMAGE}

	#call each configuration method
	for conf in $confs; do
		__${IMAGE}_${conf}
	done
}

################################  MAIN

__main "$@"

_exit 0
