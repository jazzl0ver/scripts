#!/usr/bin/perl
# $Id$
#
# check_mysql_longqueries plugin for Nagios
#
# Copyright (C) 2009  Vincent Rivellino <vrivellino@paybycash.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
# Checks MySQL's processlist to see if there are queries running longer than
# defined thresholds.
#
# Requires the following modules:
#        DBI
#        Nagios::Plugin
#
# Copyright Notice: GPLv2
#
# CHANGES
#
# 30 Jan 2009 - Vincent Rivellino <vrivellino@paybycash.com>
#               Initial version released.
#


use warnings;
use strict;
use DBI;
use Nagios::Plugin;


## setup Nagios::Plugin
my $np = Nagios::Plugin->new(
        usage    => "Usage: %s [-v|--verbose] [-H <host>] [-P <port>] [-S <socket>] [-u <user>] [-p <password>] [-C <path/to/defaults>] -w <warn time> -c <crit time>",
        version  => "1.1",
        license  => "Copyright (C) 2009  Vincent Rivellino <vrivellino\@paybycash.com>\n" .
              "This plugin comes with ABSOLUTELY NO WARRANTY.  This is free software, and you\n" .
              "are welcome to redistribute it under the conditions of version 2 of the GPL."
);

## add command line arguments
$np->add_arg(
        spec => 'host|H=s',
        help => "-H, --host\n   MySQL server host"
);
$np->add_arg(
        spec => 'port|P=i',
        help => "-P, --port\n   MySQL server port"
);
$np->add_arg(
        spec => 'socket|S=s',
        help => "-S, --socket\n   MySQL server socket"
);
$np->add_arg(
        spec => 'user|u=s',
        help => "-u, --user\n   database user (must have privilege to SHOW PROCESSLIST)"
);
$np->add_arg(
        spec => 'password|p=s',
        help => "-p, --password\n   database password"
);
$np->add_arg(
        spec => 'warn|w=i',
        help => "-w, --warn\n   Query time in seconds to generate a WARNING",
        required => 1
);
$np->add_arg(
        spec => 'crit|c=i',
        help => "-c, --crit\n   Query time in seconds to generate a CRITICAL",
        required => 1
);
$np->add_arg(
        spec => 'db=s',
        help => "--db\n   Only check queries running on this database\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'skip_db=s',
        help => "--skip_db\n   Don't check queries running on this database\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'clientuser=s',
        help => "--clientuser\n   Only check queries running by this MySQL user\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'skip_clientuser=s',
        help => "--skip_clientuser\n   Don't check queries running by this MySQL user\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'clienthost=s',
        help => "--clienthost\n   Only check queries running from this client host\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'skip_clienthost=s',
        help => "--skip_clienthost\n   Don't check queries running from this client host\n   To specify more than one, separate with commas."
);
$np->add_arg(
        spec => 'default_config|C=s',
        help => "--default_config\n   Use defaults from the file specified."
);


## parse the command line arguments
$np->getopts;
my $verbose = $np->opts->verbose || 0;

if ( $verbose >= 2 ) {
        print "Plugin options:\n";
        printf "    %-23s %d\n", "verbose:", $verbose;
        printf "    %-23s %s\n", "host:", $np->opts->host || '';
        printf "    %-23s %s\n", "port:", $np->opts->port || '';
        printf "    %-23s %s\n", "socket:", $np->opts->socket || '';
        printf "    %-23s %s\n", "user:", $np->opts->user || '';
        printf "    %-23s %s\n", "password:", $np->opts->password || '';
        printf "    %-23s %d\n", "warn:", $np->opts->warn;
        printf "    %-23s %d\n", "crit:", $np->opts->crit;
        printf "    %-23s %s\n", "db:", $np->opts->db || '';
        printf "    %-23s %s\n", "skip_db:", $np->opts->skip_db || '';
        printf "    %-23s %s\n", "clientuser:", $np->opts->clientuser || '';
        printf "    %-23s %s\n", "skip_clientuser:", $np->opts->skip_clientuser || '';
        printf "    %-23s %s\n", "clienthost:", $np->opts->clienthost || '';
        printf "    %-23s %s\n", "skip_clienthost:", $np->opts->skip_clienthost || '';
        printf "    %-23s %s\n", "default_config:", $np->opts->default_config || '';
}

# extract restrictions from args - will grep() these lists
my @db     = split( '/,/', $np->opts->db      || '' );
my @skipdb = split( '/,/', $np->opts->skip_db || '' );
my @clientuser     = split( '/,/', $np->opts->clientuser      || '' );
my @skipclientuser = split( '/,/', $np->opts->skip_clientuser || '' );
my @clienthost     = split( '/,/', $np->opts->clienthost      || '' );
my @skipclienthost = split( '/,/', $np->opts->skip_clienthost || '' );

alarm $np->opts->timeout;

## setup the dsn - no need to specify a database
my $dsn = 'DBI:mysql:';

## if we're connecting to localhost (by name) or the host isn't defined ...
if ( ! $np->opts->host || $np->opts->host eq 'localhost' ) {
        # connect via a local socket (if it's defined)
        $dsn .= ';mysql_socket=' . $np->opts->socket
                if $np->opts->socket;

## otherwise, attempt to connect via host and/or port (if they're defined)
} else {
        $dsn .= ';host=' . $np->opts->host
                if $np->opts->host;
        $dsn .= ';port=' . $np->opts->port
                if $np->opts->port;
        $dsn .= ';mysql_read_default_file=' . $np->opts->default_config
                if $np->opts->default_config;
}

## print dsn if really verbose
print "DSN: '$dsn'  USER: '", $np->opts->user || '', "' PASS: '", $np->opts->password || '', "'\n"
        if $verbose >= 2;

## connect to the database server
my $dbh = DBI->connect( $dsn, $np->opts->user || '', $np->opts->password || '',
                        { RaiseError => 0, PrintError => 0, AutoCommit => 1 } )
        or $np->nagios_exit( UNKNOWN, "Could not connect to database: $DBI::errstr" );

## get the list of running queries
my $sth = $dbh->prepare( 'SHOW FULL PROCESSLIST' );
$sth->execute();
$np->nagios_exit( UNKNOWN, $sth->errstr ) if $sth->err;

## bind each row result to a hash
my %row;
$sth->bind_columns( \( @row{ @{$sth->{NAME_lc} } } ));


## use these to keep track of the longest-running query
my $longquery_info = '';
my $longquery_time = 0;

## process the results
my $count = 0;
while ( $sth->fetch ) {
        $count++;

        # skip if time is zero or NULL
        next unless $row{'time'};

        # skip ignorable results
        next if $row{'user'} eq 'system user';
        next if $row{'command'} =~ m/(Sleep|Binlog Dump|Ping|Processlist|Daemon)/io;

        # extract connection info
        my $db = $row{'db'} || '';
        my $user = $row{'user'} || '';
        my $host = $row{'host'} || '';
        $host =~ s/:\d+$//o;

        # skip if connection info does or doest match criteria
        next if $np->opts->db and grep !/^$db$/, @db;
        next if $np->opts->skip_db and grep /^$db$/, @skipdb;

        next if $np->opts->clientuser and grep !/^$user$/, @clientuser;
        next if $np->opts->skip_clientuser and grep /^$user$/, @skipclientuser;

        next if $np->opts->clienthost and grep !/^$host$/, @clienthost;
        next if $np->opts->skip_clienthost and grep /^$host$/, @skipclienthost;

        # only save the longest running query
        if ( $row{'time'} > $longquery_time ) {
                $longquery_time = $row{'time'};
                $longquery_info = "TIME: $row{'time'}";
                foreach my $k ( sort keys %row ) {
                        next if $k eq 'time' or $k eq 'info';
                        $longquery_info .= " $k=" . ( $row{$k} || 'NULL' );
                }
                $longquery_info .= " INFO=" . ( $row{'info'} || 'NULL' );
        }
}

# we're done with the db handle
$dbh->disconnect;

# OK if no long queries were found
$np->nagios_exit( OK, "No long running queries found ($count threads checked)" ) unless $longquery_info;

# check for crit
$np->nagios_exit( CRITICAL, $longquery_info ) if $longquery_time >= $np->opts->crit;
$np->nagios_exit( WARNING, $longquery_info ) if $longquery_time >= $np->opts->warn;

# OK if if the longest query didn't match crit & warn
$np->nagios_exit( OK, "No long running queries found ($count threads checked)" );
