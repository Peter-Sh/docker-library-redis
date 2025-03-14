#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
	set -- redis-server "$@"
fi

CMD=$(realpath $(command -v "$1") 2>/dev/null || :)
# drop pivileges only if our uid is 0 (`--user` is not set)
if [ \( "$CMD" = '/usr/local/bin/redis-server' -o "$CMD" = '/usr/local/bin/redis-sentinel' \) -a "$(id -u)" = '0' ]; then
	find . \! -user redis -exec chown redis '{}' +
	SECUREBITS_ARG=""
	if /usr/bin/setpriv -d | grep -q 'Capability bounding set:.*setpcap'; then
		# we have setpcap, use it to lock down securebits
		SECUREBITS_ARG="--securebits=+noroot,+noroot_locked,+no_setuid_fixup,+no_setuid_fixup_locked,+keep_caps_locked"
	fi
	exec /usr/bin/setpriv \
		--reuid redis \
		--regid redis \
		--clear-groups \
		--nnp \
		--bounding-set=-all \
		$SECUREBITS_ARG \
		"$0" "$@"
fi

# set an appropriate umask (if one isn't set already)
# - https://github.com/docker-library/redis/issues/305
# - https://github.com/redis/redis/blob/bb875603fb7ff3f9d19aad906bd45d7db98d9a39/utils/systemd-redis_server.service#L37
um="$(umask)"
if [ "$um" = '0022' ]; then
	umask 0077
fi

if [ "$1" = 'redis-server' ]; then
	echo "Starting Redis Server"
	modules_dir="/usr/local/lib/redis/modules/"
	
	if [ ! -d "$modules_dir" ]; then
		echo "Warning: Default Redis modules directory $modules_dir does not exist."
	elif [ -n "$(ls -A $modules_dir 2>/dev/null)" ]; then
		for module in "$modules_dir"/*.so; 
		do
			if [ ! -s "$module" ]; then
				echo "Skipping module $module: file has no size."
				continue
			fi
			
			if [ -d "$module" ]; then
				echo "Skipping module $module: is a directory."
				continue
			fi
			
			if [ ! -r "$module" ]; then
				echo "Skipping module $module: file is not readable."
				continue
			fi

			if [ ! -x "$module" ]; then
				echo "Warning: Module $module is not executable."
				continue
			fi
			
			set -- "$@" --loadmodule "$module"
		done
	fi
fi


exec "$@"
