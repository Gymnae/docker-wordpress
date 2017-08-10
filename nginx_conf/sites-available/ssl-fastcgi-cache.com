# Define path to cache and memory zone. The memory zone should be unique.
# keys_zone=ssl-fastcgi-cache.com:100m creates the memory zone and sets the maximum size in MBs.
# inactive=60m will remove cached items that haven't been accessed for 60 minutes or more.
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=MYSITE:500m inactive=600m;
fastcgi_cache_path /var/run/nginx-cache2 levels=1:2 keys_zone=MYSITE2:100m inactive=60m;

server {
	# Ports to listen on, uncomment one.
	listen 80;
	listen [::]:80;

	# Server name to listen for
	server_name ssl-fastcgi-cache.com;

	# Path to document root
	root /sites/ssl-fastcgi-cache.com/public;

	# File to be used as index
	index index.php;

	# Overrides logs defined in nginx.conf, allows per site logs.
	access_log /sites/ssl-fastcgi-cache.com/logs/access.log;
	error_log /sites/ssl-fastcgi-cache.com/logs/error.log;

	# Default server block rules
	include global/server/defaults.conf;

	# Fastcgi cache rules
	include global/server/fastcgi-cache.conf;
	
	# cache rules for "cache enabler" wordpress plugin
	#include global/server/wp-cache-enabler.conf;

	# SSL rules
	include global/server/ssl.conf;


    location ~* ^.+\.(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|css|rss|atom|js|jpg|jpeg|gif|png|ico|zip|tgz|gz|webp|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$
    {
        access_log off;
        log_not_found off;
        expires max;
    }
    
    location ~ /\. { deny  all; access_log off; log_not_found off; }
    
  
  # Deny public access to wp-config.php
location ~* wp-config.php {
    deny all;
}
	# Deny access to wp-login.php
#   location = /wp-login.php {
#    limit_req zone=MYSITE2 burst=1 nodelay;
#    fastcgi_pass unix:/run/php/php7.0-fpm.sock;
#}

}
