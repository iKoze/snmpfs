#!/usr/bin/perl -w
# 
# snmpfsd
# simple network management for stupids (daemon)
# 
# dev-start: 17.4.2014
# Created by Florian Schiessl <florian at floriware.de>
# Licensed under the MIT License
# 
# Generate Certificates:
# openssl req -new -x509 -newkey rsa:1024 -days 3650 -keyout server-key.pem -out server-cert.pem
# openssl rsa -in server-key.pem -out server-key.pem
#

use strict;
use Socket;
use HTTP::Daemon;
use HTTP::Daemon::SSL;
use HTTP::Daemon::App;
use HTTP::Status;
use Data::Dumper;

####
# Basic setup
my $plugindir = "./plugins-enabled";
my $listen_ip = '0.0.0.0';
my $listen_port = 3673;
# Safe-Mode
# 0: Re-find all nodes after every successful client authentication. (slow, no daemon restart required after plugin change)
# 1: Find all nodes at daemon startup
my $safe_mode = 1;

####
# SSL setup
my $use_ssl = 0;
my $ssl_cert_file = "./certs/server-cert.pem";
my $ssl_key_file = "./certs/server-key.pem";

####
# Allowed hosts setup
my $use_allowed_hosts = 1;
# Check client IP is in this list
my @allowed_ips = qw( 127.0.0.1 );
# or do a forward lookup of those names and use the result against client IP
# Useful for DDNS.
my @allowed_names = qw( monitoring.example.com );

####
# Authentification setup
my $use_auth = 1;
my $realm_name = 'snmpfs requires auth!';
my %users = (
	testuser => "2323"
);

####
# Metainformation
my $version = "0.1"; # Version string
my $info = "
snmpfsd version $version
"; # Some information which is sent out after EOF


#### START ####
my %allowed_hosts = map { $_ => 1 } @allowed_ips;

my @files;
&readdir();

$SIG{CHLD} = 'IGNORE';

my $d;
if ($use_ssl)
{
	$d = HTTP::Daemon::SSL->new(
		LocalAddr => $listen_ip,
		LocalPort => $listen_port,
		Reuse => 1,
		SSL_cert_file => $ssl_cert_file,
		SSL_key_file => $ssl_key_file
	) || die;
}
else
{
	$d = HTTP::Daemon->new(
		LocalAddr => $listen_ip,
		LocalPort => $listen_port,
		Reuse => 1,
	) || die;
}

print "snmpfsd running at <URL:", $d->url, ">\n";

####
# Mainloop
while (1)
{
	my $conn = $d->accept;
	if (fork() == 0)
	{
		exit if !defined($conn);
		if ($use_allowed_hosts && !&checkClient($conn->peerhost()))
		{
			# Client not in allowed_hosts
			exit; # Just close the connection and pretend nobody is at home.
		}
		my $r = $conn->get_request;
		if (defined($r) && $r->method eq 'GET')
		{
			if ($use_auth)
			{
				my ($auth_user, $auth_pass) = HTTP::Daemon::App::decode_basic_auth($r);
				if (!defined($auth_user) || !(exists $users{$auth_user} && $users{$auth_user} == $auth_pass))
				{
					HTTP::Daemon::App::send_basic_auth_request($conn, $realm_name);
					exit;
				}
				print "Login: $auth_user, $auth_pass\n";
			}
			&readdir() if !$safe_mode;
			my $path = $r->uri->path;
			if ($path eq "/")
			{
				# Print nodes list
				print $conn &getIndex;
			}
			elsif (grep {$_ eq $path} @files)
			{
				# Print result of node
				print $conn &execute($path);
			}
			else
			{
				# Nonexisting node
				$conn->send_error(404);
			}
		}
		else
		{
			# Server did not understood the request.
			$conn->send_error(400);
		}
		$conn->close;
		undef($conn);
		exit;
	}
}

####
# Allowed hosts processing
sub checkClient
{
	my $ip = $_[0];
	return 1 if exists($allowed_hosts{$ip}); # IP is in @allowed_ips
	# Only do Forward-lookup if ip lookup failed
	foreach(@allowed_names)
	{
		my $packed_ip = gethostbyname($_);
		if (defined $packed_ip)
		{
			$allowed_hosts{inet_ntoa($packed_ip)} = 1; # Add Result of forward lookup
		}
	}
	return 1 if exists($allowed_hosts{$ip}); # re-check
	return 0;
}

####
# Generates nodes index
sub getIndex
{
	my $r = "snmpfs: $version\nnodes:\n";
	$r.= join("\n", @files);
	$r.= "\nEOF\n$info";
	return $r;
}

####
# Executes a node request
sub execute
{
	my $node = $_[0];
	my @parts = split("/", $node);
	my $path = $plugindir;
	for (my $i = 1; $i <= $#parts; $i++)
	{
		$path .= "/".$parts[$i];
		next if -d $path; # search file in next directory
		if (-x $path)
		{
			# Execute file with remaining nodes as parameter
			my $cmd = $path." ".join("/", @parts[$i+1 .. $#parts]);
			return `$cmd`;
		}
		if (-r $path)
		{
			# read textfile
			open FILE, $path;
			my @content = <FILE>;
			close FILE;
			return join("", @content) || "EOF"; # Append EOF if empty
		}
	}
}

####
# Finds nodes
sub readdir
{
	@files = ();
	my $subdir = $_[0];
	my $root = $plugindir;
	my $combined = $root;
	if (defined($subdir))
	{
		$combined .= $subdir;
	}
	else
	{
		$subdir = "";
	}
	opendir(my $dh, $combined);
	while(readdir $dh)
	{
		next if m/^(\.)|(\.\.)$/; # Do not process . and ..
		my $file = $_;
		my $path = $combined."/".$file;
		my $subpath = $subdir."/".$file;
		if (-d $path)
		{
			&readdir($subpath); # also check out subdirectories
		}
		else
		{
			if (-x $path)
			{
				# File is executeable
				my $res = `$path /`;
				if ($res =~ s/^nodes:\n//)
				{
					# File responses to / request. Add subnodes to nodes list.
					my @subnodes = split("\n", $res);
					foreach (@subnodes)
					{
						next if m/^\s*$/; # Ignore empty lines
						next if m/^\s*#/; # Ignore comments
						last if m/^EOF$/; # Ignore everything after EOF
						if (m/^\/$/)
						{
							push(@files, $subpath);
						}
						else
						{
							push(@files, $subpath."/".$_);
						}
					}
				}
				else
				{
					# File seems to be single-node.
					push(@files, $subpath);
				}
			}
			else
			{
				# Normal textfile
				push(@files, $subpath);
			}
		}
	}
	closedir $dh;
}
