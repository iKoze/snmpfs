#!/usr/bin/perl -w
# 
# snmpfsd
# simple network management for stupids (daemon)
# 
# Created by Florian Schiessl <florian at floriware.de>
# Licensed under the MIT License
# 

use strict;
use HTTP::Daemon::SSL;
use HTTP::Status;
use Data::Dumper;

my $plugindir = "./plugins";

my @files;
&readdir();

$SIG{CHLD} = 'IGNORE';
my $d = HTTP::Daemon->new(
	LocalPort => 2323,
	Reuse => 1
	) || die;
print "Please contact me at: <URL:", $d->url, ">\n";
while (1)
{
	(my $conn, my $peer_addr) = $d->accept;
	if (fork() == 0)
	{
		my $r = $conn->get_request;
		if (defined($r) && $r->method eq 'GET')
		{
			my $path = $r->uri->path;
			if ($path eq "/")
			{
#				$conn->send_status_line;
#				$conn->send_basic_header;
				print $conn &getIndex;
			}
			elsif (grep {$_ eq $path} @files)
			{
				print $conn &execute($path);
			}
			else
			{
				$conn->send_error(404);
			}
		}
		else
		{
			#$conn->send_error(RC_FORBIDDEN);
			$conn->send_error(404);
		}
		$conn->close;
		undef($conn);
		exit;
	}
}

sub getIndex
{
	my $r = "snmpfs: 0.1\nnodes:\n";
	$r.= join("\n", @files);
	$r.= "\nEOF\n\n\n";
	$r.= "snmpfsd";
	return $r;
}

sub execute
{
	my $node = $_[0];
	my @parts = split("/", $node);
	my $path = $plugindir;
	my $res = "";
	for (my $i = 1; $i <= $#parts; $i++)
	{
		$path .= "/".$parts[$i];
		next if -d $path;
		if (-x $path)
		{
			my $cmd = $path." ".join("/", @parts[$i+1 .. $#parts]);
			return `$cmd`;
		}
		if (-r $path)
		{
			open FILE, $path;
			my @content = <FILE>;
			close FILE;
			return join("", @content);
		}
	}
}

sub readdir
{
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
		next if m/^(\.)|(\.\.)$/;
		my $file = $_;
		my $path = $combined."/".$file;
		my $subpath = $subdir."/".$file;
		if (-d $path)
		{
			&readdir($subpath);
		}
		else
		{
			if (-x $path)
			{
				my $res = `$path /`;
				if ($res =~ s/^nodes:\n//)
				{
					my @subnodes = split("\n", $res);
					foreach (@subnodes)
					{
						next if m/^\s*$/;
						next if m/^\s*#/;
						last if m/^EOF$/;
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
					push(@files, $subpath);
				}
			}
			else
			{
				push(@files, $subpath);
			}
		}
	}
	closedir $dh;
}
