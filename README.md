# Hogwaltz
## NGINX and Lua (OpenResty)-based L7 anti-bot/DoS script
Inspiration drawn by: 
https://github.com/C0nw0nk/Nginx-Lua-Anti-DDoS
https://github.com/TecharoHQ/anubis

Hogwaltz works in a very similar way to the above projects:

When a client makes a request to a protected location, it is presented with a JavaScript-based computational challenge. This challenge usually requires a working JavaScript engine, which majority of the bots (currently) do not have. 
If the challenge is solved, client is allowed to access the content. In case client sends too many requests without passing the challenge, then it will be considered an attacker, and all subsequent connections from this attacker's IP address will be TCP-reset without sending any response. 
There is also an option to notify an external API (for example, a firewall) of an attack.

The main difference from aforementioned projects is that this script is stateful. It uses memcached for storing runtime data. Memcached was chosen for it's very high resource efficiency and 'key expiration' feature.

I created this project mainly because I wanted something that is very easy to integrate with nginx, but also highly scale-able and configurable to an extent.
Please keep in mind that this is not a complete solution, but more like a template, which you can modify to your needs. I made this script in my spare time; there is a lot of room for optimization and epic bugs may be present.
