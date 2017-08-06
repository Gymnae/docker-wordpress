# Define path to cache and memory zone. The memory zone should be unique.
# keys_zone=ssl-fastcgi-cache.com:100m creates the memory zone and sets the maximum size in MBs.
# inactive=60m will remove cached items that haven't been accessed for 60 minutes or more.
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=MYSITE:500m inactive=600m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;

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

	# SSL rules
	include global/server/ssl.conf;
	
	set $skip_cache 0;

	location / {
		try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		try_files $uri =404;
		include global/fastcgi-params.conf;

		# Change socket if using PHP pools or PHP 5
		fastcgi_pass unix:/run/php/php7.0-fpm.sock;
		#fastcgi_pass unix:/var/run/php5-fpm.sock;

		# Skip cache based on rules in global/server/fastcgi-cache.conf.
		fastcgi_cache_bypass $skip_cache;
		fastcgi_no_cache $skip_cache;

		# Define memory zone for caching. Should match key_zone in fastcgi_cache_path above.
		#fastcgi_cache ssl-fastcgi-cache.com;

		# Define caching time.
		#fastcgi_cache_valid 60m;
		
		fastcgi_cache MYSITE;
		fastcgi_cache_valid 200 60m;
	}
	
	location ~ /purge(/.*) {
	    fastcgi_cache_purge MYSITE "$scheme$request_method$host$1";
	}	


	# Uncomment if using the fastcgi_cache_purge module and Nginx Helper plugin (https://wordpress.org/plugins/nginx-helper/)
	# location ~ /purge(/.*) {
	#	fastcgi_cache_purge ssl-fastcgi-cache.com "$scheme$request_method$host$1";
	# }
}
