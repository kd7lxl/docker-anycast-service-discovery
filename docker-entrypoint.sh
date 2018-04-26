#!/bin/bash
#
# Copyright 2018 Tom Hayward <tom@tomh.us>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

DOCKER_SOCK=${DOCKER_SOCK:-/var/run/docker.sock}


add_interface() {
	IFACE=$1
	ADDR=$2
	echo Adding $IFACE with address $ADDR
	ip tuntap add dev $IFACE mode tap
	ip link set dev $IFACE mtu 1418
	ip addr add $ADDR dev $IFACE
}


remove_interface() {
	ip tuntap del dev $1 mode tap
}


open_firewall() {
	iptables -${3:-A} INPUT -p tcp -d $1 -m multiport --dports $2 -j ACCEPT 2>/dev/null
}


close_firewall() {
	open_firewall $1 $2 D
}


advertise() {
	ip link set dev $1 ${2:-up}
}


disable_advertisement() {
	advertise $1 down
}


ports() {
	# converts exposed ports from docker metadata to a comma-separated list of ports for iptables
	docker inspect $1 | jq -r '.[0].NetworkSettings.Ports | map(select(. != null)) | map(.[].HostPort) | join(",")'
}


trap 'trap - SIGTERM && kill 0' SIGINT SIGTERM EXIT


# recreate interfaces after reboot
docker container ls --all --quiet --filter 'label=anycast.address' | while read ID
do
	IFACE=any-${ID:0:10}
	INSPECT=$(docker inspect $ID)
	ADDR=$(echo "$INSPECT" | jq -r '.[0].Config.Labels["anycast.address"]')
	HEALTH=$(echo "$INSPECT" | jq -r '.[0].State.Health.Status')
	add_interface $IFACE $ADDR
	if [ "$HEALTH" = "healthy" ]
	then
		open_firewall $ADDR $(ports $ID)
		advertise $IFACE
	else
		docker restart $ID &
	fi
done


# wait for events
docker events --filter 'label=anycast.address' --filter 'type=container' --format '{{json .}}' | while read event
do
	STATUS=$(echo "$event" | jq -r '.status')
	ID=$(echo "$event" | jq -r '.id')
	FROM=$(echo "$event" | jq -r '.from')
	ADDR=$(echo "$event" | jq -r '.Actor.Attributes["anycast.address"]')
	#SERVICE=$(echo "$event" | jq -r '.Actor.Attributes["com.docker.compose.service"]')
	# Linux maximum interface name length is 15 characters
	IFACE=any-${ID:0:10}
	case "$STATUS" in
		"create")
			echo $FROM created
			add_interface $IFACE $ADDR
			;;
		"start")
			echo $FROM started
			# nothing to do until it's healthy
			;;
		"health_status: healthy")
			echo $FROM became healthy
			open_firewall $ADDR $(ports $ID)
			advertise $IFACE
			;;
		"health_status: unhealthy")
			echo $FROM unhealthy, pulling advertisement
			disable_advertisement $IFACE
			;;
		"die"|"kill"|"stop")
			echo $FROM stopped, pulling advertisement
			disable_advertisement $IFACE
			close_firewall $ADDR $(ports $ID)
			;;
		"destroy")
			echo $FROM destroyed, removing $IFACE
			remove_interface $IFACE
			;;
		exec_*)
			# ignore exec_create, exec_start, and exec_die.
			# They're noisy due to frequent health checks.
			;;
		*)
			echo unhandled: $STATUS on $ID
	esac
done
