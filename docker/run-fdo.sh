#!/bin/bash



# sudo iptables -A PREROUTING -t nat -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 8040
# sudo iptables -A PREROUTING -t nat -i eth0 -p tcp --dport 443 -j REDIRECT --to-port 8040

# sudo apt-get install iptables-persistent

# sudo /sbin/iptables-save > /etc/iptables/rules.v4
# sudo /sbin/ip6tables-save > /etc/iptables/rules.v6


grabCreds() {
    components=("manufacturer" "rv" "owner")
    for i in ${components[@]}; do
        if [[ "${components[@]}" =~ "$i" ]]; then

            keypwd="$(grep -E '^ *api_password=' fdo/pri-fidoiot-v1.1.0.2/$i/service.env)"
            API_PWD=${keypwd#api_password=}
           
	    echo export "$i"=$API_PWD
        fi
    done
  

}

grabCreds

#OWNER SERVICES API PASSWORD
api_password=XhvVT0F7WEMURjm
#RV PASSWORD
api_password=KR4bmIOEK7eoEF9e
#MANUFACTURER PASSWORD
api_password=xjvFfoeAKDLrMplr


#REMEMBER TO COMMENT OUT (org.fidoalliance.fdo.protocol.StandardOwnerSchemeSupplier) in the owner/service.yml
#UNCOMMENT (org.fidoalliance.fdo.protocol.HttpOwnerSchemeSupplier) ONLY FOR DEVELOPMENT


#Ping Servers
curl -D - --digest -u apiUser:$owner --location --request GET 'http://localhost:8042/health'

curl -D - --digest -u apiUser:$rv --location --request GET 'http://localhost:8040/health'

curl -D - --digest -u apiUser:$manufacturer --location --request GET 'http://localhost:8039/health'

192.168.0.26
curl -D - --digest -u apiUser:$owner --location --request GET 'http://192.168.0.26:8042/health'


#1. POST instructions for manufacturer to redirect device to correct RV server. Instructions in CBOR
curl -D - --digest -u apiUser:$manufacturer --location --request POST 'http://192.168.0.26:8039/api/v1/rvinfo' --header 'Content-Type: text/plain' --data-raw '[[[5,"192.168.0.26"],[3,8040],[12,1],[2,"192.168.0.26"],[4,8040]]]' # Configures for TLS -> '[[[5,"localhost"],[3,8040],[12,1],[2,"127.0.0.1"],[4,8041]]]'

curl -D - --digest -u apiUser:$manufacturer --location --request POST 'http://localhost:8039/api/v1/rvinfo' --header 'Content-Type: text/plain' --data-raw '[[[5,"localhost"],[3,8040],[12,2],[2,"127.0.0.1"],[4,8040]]]' # Configures for TLS -> '[[[5,"localhost"],[3,8040],[12,1],[2,"127.0.0.1"],[4,8041]]]'


curl -D - --digest -u apiUser:$manufacturer --location --request POST 'http://localhost:8039/api/v1/rvinfo' --header 'Content-Type: text/plain' --data-raw '[[[5,"192.168.0.237"],[3,8040],[12,2],[2,"192.168.0.237"],[4,8040]]]' # Configures for TLS -> '[[[5,"localhost"],[3,8040],[12,1],[2,"127.0.0.1"],[4,8041]]]'


curl -D - --digest -u apiUser:$manufacturer --location --request GET 'http://localhost:8039/api/v1/rvinfo' --header 'Content-Type: text/plain'


#2. Update device service.yml file to point DI process to pri-fdo-mfg component. Then run device.jar -> This will return the device guid you just initialized
cd device
java -jar device.jar


90c1b6ee-ae5d-46c9-bfa4-8000428c428a

#3. GUID is 90c1b6ee-ae5d-46c9-bfa4-8000428c428a -> to check this run the following API call -> this is also how you get the device serial number
curl -D - --digest -u apiUser:$manufacturer --location --request GET 'http://192.168.0.26:8039/api/v1/deviceinfo/100000000' --header 'Content-Type: text/plain'
curl -D - --digest -u apiUser:$manufacturer --location --request GET 'http://localhost:8039/api/v1/deviceinfo/100000000' --header 'Content-Type: text/plain'



curl -D - --digest -u apiUser:$owner --location --request GET 'http://localhost:8042/api/v1/ondie'


#4.Now GET the public key from owner services
#OWNER SERVICES API PASSWORD
api_password=XhvVT0F7WEMURjm

curl -D - --digest -u apiUser:$owner --location --request GET 'http://localhost:8042/api/v1/certificate?alias=SECP256R1' --header 'Content-Type: text/plain' -o pubkey.pem
curl -D - --digest -u apiUser:$owner --location --request GET 'http://192.168.0.26:8042/api/v1/certificate?alias=SECP256R1' --header 'Content-Type: text/plain' -o pubkey.pem



#5. Next you POST the public key and serial number (63BA14BC) to the manufacturer to get the ownership voucher 
export owner_certificate=pubkey.pem

#MANUFACTURER
curl -D - --digest -u apiUser:$manufacturer --location --request POST "http://localhost:8039/api/v1/mfg/vouchers/4903D778" --header 'Content-Type: text/plain' --data-binary '@pubkey.pem' -o owner_voucher.txt

curl -D - --digest -u apiUser:$manufacturer --location --request POST "http://192.168.0.26:8039/api/v1/mfg/vouchers/FF2379F8" --header 'Content-Type: text/plain' --data-binary '@pubkey.pem' -o owner_voucher.txt




curl -D - --digest -u apiUser:$owner --location --request GET "http://localhost:8042/api/v1/owner/vouchers" --header 'Content-Type: text/plain'

#6. POST the ownership voucher ($SERIAL_voucher.txt) found obtained from the manufacturer to Owner services

curl -D - --digest -u apiUser:$owner --location --request POST "http://localhost:8042/api/v1/owner/vouchers" --header 'Content-Type: text/plain' --data-binary '@owner_voucher.txt'
curl -D - --digest -u apiUser:$owner --location --request POST "http://192.168.0.26:8042/api/v1/owner/vouchers" --header 'Content-Type: text/plain' --data-binary '@owner_voucher.txt'

#Response body will be the ownership voucher uuid (90c1b6ee-ae5d-46c9-bfa4-8000428c428a)

#7. Now Configure the Owners TO2 address using the following API
#TLS port 8043,5
curl -D - --digest -u apiUser:$owner --location --request POST 'http://localhost:8042/api/v1/owner/redirect' --header 'Content-Type: text/plain' --data-raw '[[null,"localhost",8042,3]]'
curl -D - --digest -u apiUser:$owner --location --request POST 'http://192.168.0.26:8042/api/v1/owner/redirect' --header 'Content-Type: text/plain' --data-raw '[[null,"192.168.0.26",8042,3]]'

#8. Next you can initiate To0 from Owner

curl -D - --digest -u apiUser:$owner --location --request GET "http://localhost:8042/api/v1/to0/90c1b6ee-ae5d-46c9-bfa4-8000428c428a" --header 'Content-Type: text/plain'
curl -D - --digest -u apiUser:$owner --location --request GET "http://192.168.0.26:8042/api/v1/to0/11e39172-b93c-4c6d-b572-2b6f352ffe4c" --header 'Content-Type: text/plain'

#Before service info package, post the script that is meant to be onboarded


curl -D - --digest -u apiUser:$owner --location --request POST 'http://localhost:8042/api/v1/owner/resource?filename=printHello.sh' --header 'Content-Type: text/plain' --data-binary '@printHello.sh'
#This is an important testing test. CReate a node definition in the exchange with the node id equal to the device guid,
#SVI has to contain the agent-install-wrapper script command with all the correct arguments(For example: node id, node token) -> refer to hzn sdo import command
#Now Configure the owner service info package

curl -D - --digest -u apiUser:$owner --location --request POST 'http://localhost:8042/api/v1/owner/svi' --header 'Content-Type: text/plain' --data-raw '[{"filedesc" : "printHello.sh","resource" : "printHello.sh"}, {"exec" : ["bash","printHello.sh"] }]'
curl -D - --digest -u apiUser:$owner --location --request POST 'http://192.168.0.26:8042/api/v1/owner/svi' --header 'Content-Type: text/plain' --data-raw '[{"filedesc" : "printHello.sh","resource" : "printHello.sh"}, {"exec" : ["bash","printHello.sh"] }]'




#GET OWNERSHIP VOUCHERS
curl -D - --digest -u apiUser:$owner --location --request GET "http://localhost:8042/api/v1/owner/vouchers" --header 'Content-Type: text/plain'

#Check status of device guid
curl -D - --digest -u apiUser:$owner --location --request GET 'http://localhost:8042/api/v1/owner/state/cf5d4654-fa6a-4e18-a19e-197cebf3d35a'