snmpfs
======

Simple Network Management Protocol - for stupids

What's this?
------------

This project should become an __easy__ alternative for the original SNMP.
(So if you're looking for an SNMP compatible daemon, you're __WRONG HERE!__)

Why not SNMP?
-------------

Because SNMP is everything, but not what it's name suggests (simple). This Project aims to 
become an easy and reliable alternative to SNMP, which is:

* simple to extend
* simple to configure
* simple to port to other systems

This is also the reason for the project's name: Simple Network Management Protocol - for stupids.
Because: If SNMP is simple, we all really have to be stupids for finding it such complicated.

How does it work?
-----------------

Basically, snmpfs is just an CGI-webserver. (That's also why it's easy portable. 
Which system today isn't running a webserver?) The first thing, the daemon will do upon upstart is, to scan 
the plugin directory. The plugin directory acts as the root of the webserver. It looks for normal text files, 
and executeable files and adds them to the node list. Executeable files will be executed on on an information 
request. Everything, they print to STDOUT will be passed to the client. Normal text files will just get sent 
out to the client as they are.
You'll receive the nodes list when querying the server without a node (HTTP GET /). If you want to query a
explicite node. You can specify it by the path from the node list. For querying the hostname, for example, 
you'll have to do a GET /hostname.

More coming soon!
-----------------
