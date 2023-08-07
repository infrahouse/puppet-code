#
# Regular cron jobs for the puppet-code package
#
0 4	* * *	root	[ -x /usr/bin/puppet-code_maintenance ] && /usr/bin/puppet-code_maintenance
