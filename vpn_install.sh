#!/bin/bash
# OpenVPN automated installation script for Debian based systems (OpenVZ virtualization)

# lets verify if TUN/TAP is available. otherwise we cannot make the tunnel
if [ ! -e /dev/net/tun ]; then
    echo "TUN/TAP is not available. Please enable it in your control panel."
    exit
fi

# here we grab our own IP address, and fallback to the internet if we cannot acquire it
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
        IP=$(wget -qO- ipv4.icanhazip.com)
fi

# start the install process and loop
if [ -e /etc/openvpn/server.conf ]; then
	while :
	do
	clear
		echo "Looks like OpenVPN is already installed"
		echo "What do you want to do?"
		echo ""
		echo "1) Add a certificate for a new user (add user)"
		echo "2) Revoke existing user certificate (remove user)"
		echo "3) Remove OpenVPN server"
		echo "4) Exit"
		echo ""
		read -p "Select an option [1-4]:" option
		case $option in
			1) 
			echo ""
			echo "Please input a logical identifier for the client"
			echo "This must be unqiue, one word only, and contain no special characters"
			read -p "Client identifier: " -e -i client CLIENT
			cd /etc/openvpn/easy-rsa/2.0/
			source ./vars
			# build-key for the client
			export KEY_CN="$CLIENT"
			export EASY_RSA="${EASY_RSA:-.}"
			"$EASY_RSA/pkitool" $CLIENT
			# Let's generate the client config
			mkdir ~/ovpn-$CLIENT
			cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/ovpn-$CLIENT/$CLIENT.conf
			cp /etc/openvpn/easy-rsa/2.0/keys/ca.crt ~/ovpn-$CLIENT
			cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.crt ~/ovpn-$CLIENT
			cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.key ~/ovpn-$CLIENT
			cd ~/ovpn-$CLIENT
			sed -i "s|cert client.crt|cert $CLIENT.crt|" $CLIENT.conf
			sed -i "s|key client.key|key $CLIENT.key|" $CLIENT.conf
			echo "remote-cert-tls server" >> $CLIENT.conf
			
			# copy into an .ovpn file
			cp $CLIENT.conf $CLIENT.ovpn
			
			echo -e "keepalive 10 60\n" >> $CLIENT.ovpn
			
			# put our certificates and keys inline so we only need one file
			echo "<ca>" >> $CLIENT.ovpn
			cat ca.crt >> $CLIENT.ovpn
			echo -e "</ca>\n" >> $CLIENT.ovpn
			
			echo "<cert>" >> $CLIENT.ovpn
			sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" $CLIENT.crt >> $CLIENT.ovpn
			echo -e "</cert>\n" >> $CLIENT.ovpn
			
			echo "<key>" >> $CLIENT.ovpn
			cat $CLIENT.key >> $CLIENT.ovpn
			echo -e "</key>\n" >> $CLIENT.ovpn
			
			# zip up the file and remove the temporary
			tar -czf ../ovpn-$CLIENT.tar.gz $CLIENT.conf ca.crt $CLIENT.crt $CLIENT.key $CLIENT.ovpn
			cd ~/
			rm -rf ovpn-$CLIENT
			echo ""
			echo "Client $CLIENT added, certificates available at ~/ovpn-$CLIENT.tar.gz"
			exit
			;;
			2)
			echo ""
			echo "Please input the existing logical identifier for the client"
			read -p "Client identifier: " -e -i client CLIENT
			cd /etc/openvpn/easy-rsa/2.0/
			. /etc/openvpn/easy-rsa/2.0/vars
			. /etc/openvpn/easy-rsa/2.0/revoke-full $CLIENT
			# If it's the first time revoking a cert, we need to add the crl-verify line
			if grep -q "crl-verify" "/etc/openvpn/server.conf"; then
				echo ""
				echo "Certificate for client $CLIENT revoked"
			else
				echo "crl-verify /etc/openvpn/easy-rsa/2.0/keys/crl.pem" >> "/etc/openvpn/server.conf"
				/etc/init.d/openvpn restart
				echo ""
				echo "Certificate for client $CLIENT revoked"
			fi
			exit
			;;
			3) 
			# remove the server and the docs
			apt-get remove --purge -y openvpn openvpn-blacklist
			rm -rf /etc/openvpn
			rm -rf /usr/share/doc/openvpn
			# remove our firewall rules
			sed -i '/--dport 53 -j REDIRECT --to-port/d' /etc/rc.local
			sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0/d' /etc/rc.local
			echo ""
			echo "OpenVPN removed!"
			exit
			;;
			4) exit;;
		esac
	done
else
	echo 'Welcome to the OpenVPN automated installer!'
	echo "You can leave the default options and the setup will be fine."
	echo ""
	echo "Which IPv4 address would you like to listen on?"
	read -p "IP address: " -e -i $IP IP
	echo ""
	echo "Which port would you like to listen on?"
	read -p "Port: " -e -i 1194 PORT
	echo ""
	echo "Would you like to listen on port 53 (DNS) as well?"
	echo "This is useful for networks that block many standard ports, but leave DNS open."
	read -p "Listen on port 53 [y/n]:" -e -i y ALTPORT
	echo ""
	echo "Please input a logical identifier for the client"
	echo "This must be unqiue, one word only, and contain no special characters"
	read -p "Client identifier: " -e -i client CLIENT
	echo ""
	read -n1 -r -p "Press any key to complete setup..."
	apt-get update
	apt-get install openvpn iptables openssl -y
	cp -R /usr/share/doc/openvpn/examples/easy-rsa/ /etc/openvpn
	# easy-rsa isn't available by default for Debian Jessie and newer
	if [ ! -d /etc/openvpn/easy-rsa/2.0/ ]; then
		wget --no-check-certificate -O ~/easy-rsa.tar.gz https://github.com/OpenVPN/easy-rsa/archive/2.2.2.tar.gz
		tar xzf ~/easy-rsa.tar.gz -C ~/
		mkdir -p /etc/openvpn/easy-rsa/2.0/
		cp ~/easy-rsa-2.2.2/easy-rsa/2.0/* /etc/openvpn/easy-rsa/2.0/
		rm -rf ~/easy-rsa-2.2.2
	fi
	cd /etc/openvpn/easy-rsa/2.0/
	cp -u -p openssl-1.0.0.cnf openssl.cnf
	# update key size to 2048 bits
	sed -i 's|export KEY_SIZE=1024|export KEY_SIZE=2048|' /etc/openvpn/easy-rsa/2.0/vars
	# Create the PKI
	. /etc/openvpn/easy-rsa/2.0/vars
	. /etc/openvpn/easy-rsa/2.0/clean-all
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --initca $*
	# Same as the last time, we are going to run build-key-server
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --server server
	export KEY_CN="$CLIENT"
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" $CLIENT
	# DH params
	. /etc/openvpn/easy-rsa/2.0/build-dh
	# Let's configure the server
	cd /usr/share/doc/openvpn/examples/sample-config-files
	gunzip -d server.conf.gz
	cp server.conf /etc/openvpn/
	cd /etc/openvpn/easy-rsa/2.0/keys
	cp ca.crt ca.key dh2048.pem server.crt server.key /etc/openvpn
	cd /etc/openvpn/
	# Set the server configuration
	sed -i 's|dh dh1024.pem|dh dh2048.pem|' server.conf
	sed -i 's|;push "redirect-gateway def1 bypass-dhcp"|push "redirect-gateway def1 bypass-dhcp"|' server.conf
	sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 8.8.8.8"|' server.conf
	sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 8.8.4.4"|' server.conf
	sed -i "s|port 1194|port $PORT|" server.conf
	# Listen at port 53 too if user wants that
	if [ $ALTPORT = 'y' ]; then
		iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT
		sed -i "/# By default this script does nothing./a\iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT" /etc/rc.local
	fi
	# Enable net.ipv4.ip_forward for the system
	sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Set iptables
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
	sed -i "/# By default this script does nothing./a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" /etc/rc.local
	# And finally, restart OpenVPN
	/etc/init.d/openvpn restart
	# Let's generate the client config
	mkdir ~/ovpn-$CLIENT
	# Try to detect a NATed connection
	# users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [ "$IP" != "$EXTERNALIP" ]; then
		echo ""
		echo "It appears that your server is behind a NAT."
		echo "If it is, please enter the external IP. Otherwise, leave the field blank."
		read -p "External IP: " -e USEREXTERNALIP
		if [ $USEREXTERNALIP != "" ]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# IP/port set on the default client.conf so we can add further users
	# without asking for them
	sed -i "s|remote my-server-1 1194|remote $IP $PORT|" /usr/share/doc/openvpn/examples/sample-config-files/client.conf
	cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/ovpn-$CLIENT/$CLIENT.conf
	cp /etc/openvpn/easy-rsa/2.0/keys/ca.crt ~/ovpn-$CLIENT
	cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.crt ~/ovpn-$CLIENT
	cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.key ~/ovpn-$CLIENT
	cd ~/ovpn-$CLIENT
	sed -i "s|cert client.crt|cert $CLIENT.crt|" $CLIENT.conf
	sed -i "s|key client.key|key $CLIENT.key|" $CLIENT.conf
	echo "remote-cert-tls server" >> $CLIENT.conf
	
	cp $CLIENT.conf $CLIENT.ovpn

	echo -e "keepalive 10 60\n" >> $CLIENT.ovpn
	
	echo "<ca>" >> $CLIENT.ovpn
	cat ca.crt >> $CLIENT.ovpn
	echo -e "</ca>\n" >> $CLIENT.ovpn
	
	echo "<cert>" >> $CLIENT.ovpn
	sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" $CLIENT.crt >> $CLIENT.ovpn
	echo -e "</cert>\n" >> $CLIENT.ovpn
	
	echo "<key>" >> $CLIENT.ovpn
	cat $CLIENT.key >> $CLIENT.ovpn
	echo -e "</key>\n" >> $CLIENT.ovpn

	tar -czf ../ovpn-$CLIENT.tar.gz $CLIENT.conf ca.crt $CLIENT.crt $CLIENT.key $CLIENT.ovpn
	cd ~/
	rm -rf ovpn-$CLIENT
	echo ""
	echo "Done!"
	echo ""
	echo "Client $CLIENT added, certificates available at ~/ovpn-$CLIENT.tar.gz"
	echo "Need more clients? Run the script again."
fi
