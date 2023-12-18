# stremio-docker
Idea here is to have both Stremio web player and server run on the same container and if IPADDRESS env variable is setup generate a certificate and use it for both.

Web player run on port 8080 and server runs on both ports 11470 ( plan http ) and 12470 (https).

1) If you exposed the ports 8080, 11470 for http just point your streaming server in settings to the lan ip address and set the server to be http://{LAN IP}:11470/ and enjoy.

2) If you set your public ip address for the IPADDRESS env variable then streamio server should set the certificate to the wild card *.519b6502d940.stremio.rocks and should generate an A record for your ip address. You should then expose ports 8080 and 12470 to your servers and then setup port forwarding to your router to point these two ports to your server.


3) If you set your private ip address to IPADDRESS then the server should still set the certificate to the wildcard *.519b6502d940.stremio.rocks and have the subdomain set as 192-168-1-10 assuming your private is is 192.168.1.10. Full domain should be 192-168-1-10.519b6502d940.stremio.rocks. You can then setup your /etc/hosts in Linux or c:\Windows\System32\Drivers\etc\hosts in windows to point that host to your lan address like :

192.168.1.10    192-168-1-10.519b6502d940.stremio.rocks

Then you can point your browser to https://192-168-1-10.519b6502d940.stremio.rocks:8080 and setup Streaming server to https://192-168-1-10.519b6502d940.stremio.rocks:12470 .

You can change the address as you can imagine.
