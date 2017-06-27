# Define path to cache and memory zone. The memory zone should be unique.
# keys_zone=ssl-fastcgi-cache.com:100m creates the memory zone and sets the maximum size in MBs.
# inactive=60m will remove cached items that haven't been accessed for 60 minutes or more.
fastcgi_cache_path /sites/ssl-fastcgi-cache.com/cache levels=1:2 keys_zone=ssl-fastcgi-cache.com:100m inactive=60m;

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
		fastcgi_cache ssl-fastcgi-cache.com;

		# Define caching time.
		fastcgi_cache_valid 60m;
	}
	
	# BEGIN BWP Minify WP Rules
	# BEGIN BWP Minify Headers
	location ~ /wp-content/plugins/bwp-minify/cache/.*\.(js|css)$ {
	    add_header Cache-Control "public, max-age=864000";
	    add_header Vary "Accept-Encoding";
	    etag off;
		}
	location ~ /wp-content/plugins/bwp-minify/cache/.*\.js\.gz$ {
	    gzip off;
	    types {}	
	    default_type application/x-javascript;
	    add_header Cache-Control "public, max-age=864000";
	    add_header Content-Encoding gzip;
	    add_header Vary "Accept-Encoding";
	    etag off;
	}
	location ~ /wp-content/plugins/bwp-minify/cache/.*\.css\.gz$ {
	    gzip off;
	    types {}
	    default_type text/css;
 	   add_header Cache-Control "public, max-age=864000";
 	   add_header Content-Encoding gzip;
 	   add_header Vary "Accept-Encoding";
 	   etag off;
		}
	# END BWP Minify Headers
	set $zip_ext "";
	if ($http_accept_encoding ~* gzip) {
   	 set $zip_ext ".gz";
}
set $minify_static "";
if ($http_cache_control = false) {
    set $minify_static "C";
    set $http_cache_control "";
}
if ($http_cache_control !~* no-cache) {
    set $minify_static "C";
}
if ($http_if_modified_since = false) {
    set $minify_static "${minify_static}M";
}
if (-f $request_filename$zip_ext) {
    set $minify_static "${minify_static}E";
}
if ($minify_static = CME) {
    rewrite (.*) $1$zip_ext break;
}
rewrite ^/wp-content/plugins/bwp-minify/cache/minify-b(\d+)-([a-zA-Z0-9-_.]+)\.(css|js)$ /index.php?blog=$1&min_group=$2&min_type=$3 last;

# END BWP Minify WP Rules

	# Uncomment if using the fastcgi_cache_purge module and Nginx Helper plugin (https://wordpress.org/plugins/nginx-helper/)
	# location ~ /purge(/.*) {
	#	fastcgi_cache_purge ssl-fastcgi-cache.com "$scheme$request_method$host$1";
	# }
}
