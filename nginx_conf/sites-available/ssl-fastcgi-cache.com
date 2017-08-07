# Define path to cache and memory zone. The memory zone should be unique.
# keys_zone=ssl-fastcgi-cache.com:100m creates the memory zone and sets the maximum size in MBs.
# inactive=60m will remove cached items that haven't been accessed for 60 minutes or more.
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=MYSITE:500m inactive=60m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;
upload_progress proxied 1m;

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
    
     set $cache_uri $request_uri;

    # bypass cache if POST requests or URLs with a query string
    if ($request_method = POST) {
        set $cache_uri 'nullcache';
    }
    if ($query_string != "") {
        set $cache_uri 'nullcache';
    }

    # bypass cache if URLs containing the following strings
    if ($request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-(app|cron|login|register|mail).php|wp-.*.php|/feed/|index.php|wp-comments-popup.php|wp-links-opml.php|wp-locations.php|sitemap(_index)?.xml|[a-z0-9_-]+-sitemap([0-9]+)?.xml)") {
        set $cache_uri 'nullcache';
    }

     # bypass cache if the cookies containing the following strings
    if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_logged_in") {
        set $cache_uri 'nullcache';
    }

    # custom sub directory e.g. /blog
    set $custom_subdir '';

    # default html file
    set $cache_enabler_uri '${custom_subdir}/wp-content/cache/cache-enabler/${http_host}${cache_uri}index.html';

    # webp html file
    if ($http_accept ~* "image/webp") {
        set $cache_enabler_uri '${custom_subdir}/wp-content/cache/cache-enabler/${http_host}${cache_uri}index-webp.html';
    }

	location / {
		try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		try_files $uri =404;
		include global/fastcgi-params.conf;

		# Change socket if using PHP pools or PHP 5
		fastcgi_pass unix:/run/php/php7.0-fpm.sock;

		# Skip cache based on rules in global/server/fastcgi-cache.conf.
		fastcgi_cache_bypass $skip_cache;
		fastcgi_no_cache $skip_cache;

		# Define memory zone for caching. Should match key_zone in fastcgi_cache_path above.
		fastcgi_cache MYSITE;
		
		fastcgi_cache_valid 200 60m;
		
	}
	
	location ~ /purge(/.*) {
	    fastcgi_cache_purge MYSITE "$scheme$request_method$host$1";
	}	


    location ~* ^.+\.(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$
    {
        access_log off;
        log_not_found off;
        expires max;
    }
    
     location ~*  \.(pdf|css|html|js|swf)$ {
        expires 30d;
    }
  
  # Deny public access to wp-config.php
location ~* wp-config.php {
    deny all;
}
#	# Deny access to wp-login.php
#    location = /wp-login.php {
#    limit_req zone=one burst=1 nodelay;
#    fastcgi_pass unix:/run/php/php7.0-fpm.sock;
#}

}
