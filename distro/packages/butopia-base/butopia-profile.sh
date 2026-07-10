# Butopia interactive shell defaults.
export EDITOR=${EDITOR:-nano}
export PAGER=${PAGER:-less}

case "$-" in
	*i*)
		PS1='butopia:\w\$ '
		alias ll='ls -lah'
		alias la='ls -A'
		;;
esac
