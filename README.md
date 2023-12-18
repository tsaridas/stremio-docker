# stremio-docker
Idea here is to have both Stremio web player and server run on the same container and if IPADDRESS env variable is setup generate a certificate and use it for both.

Web player run on port 8080 and server runs on both ports 11470 ( plan http ) and 12470 (https).
