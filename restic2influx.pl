#!/usr/bin/perl
#
# restic2influx.pl -- parse restic status messages and feed them to influxdb
#
# (C) 2021 Hajo Noerenberg
#
# http://www.noerenberg.de/
# https://github.com/hn/restic2influx
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.0 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.txt>.
#

# apt-get install libjson-perl libinfluxdb-lineprotocol-perl libwww-perl

use strict;
use POSIX qw(strftime);
use JSON qw(decode_json);
use InfluxDB::LineProtocol qw(data2line);
use LWP::UserAgent;

my $debug;
my $summary;
my $repo;
my $influxhost = 'http://localhost:8086';
my $influxdb;
my $start = time();

foreach my $arg ( @ARGV ) {
    $summary++, next if ($arg eq "-s");
    $debug++, next if ($arg eq "-d");
    $repo = $arg, next if (!$repo);
    $influxdb = $arg, next if (!$influxdb);
    $influxhost = $arg;
}

die("Usage: $0 [-d] [-s] <restic repository> <influx db> [influx host]") if ( !$repo || !$influxdb);

while ( my $line = <STDIN> ) {

# {"message_type":"status","percent_done":0,"total_files":1,"total_bytes":60064}
# {"message_type":"summary","files_new":0,"files_changed":0,"files_unmodified":8864,"dirs_new":0,"dirs ...

    my $message = decode_json($line) || next;

    if ( $message->{"message_type"} eq "status" ) {
        my $files = $message->{"total_files"};
        while ( $files =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { };   # add thousands separator
        my $mbytes = int ( $message->{"total_bytes"} / 1048576 );
        while ( $mbytes =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { }
        my $percent = $message->{"percent_done"};
        $0 = "restic2influx " . $repo
          . " [Done: " . sprintf( "%.2f%%", $percent * 100 )
          . " ETA: " . ( ( $percent > 0 ) ? strftime "%m-%d %H:%M", localtime( $start + ( ( time() - $start ) / $percent ) ) : "unknown" )
          . " Files: " . $files
          . " MBytes: " . $mbytes . "]";

    } elsif ( $message->{"message_type"} eq "summary" ) {
        foreach my $key ( sort keys %{$message} ) {
            printf "%23s: %s\n", $key, $message->{$key} if ($summary);
        }
        my $snapshot = $message->{'snapshot_id'};
        delete ${$message}{'snapshot_id'};
        delete ${$message}{'message_type'};
        my $influxreq = data2line(
            'restic',
            $message,
            { 'repo' => $repo, 'snapshot' => $snapshot }
        );

        if ($debug) {
            print $influxreq . "\n";
        } else {
            my $ua       = LWP::UserAgent->new();
            my $response = $ua->post(
                $influxhost . '/write?precision=ns&db=' . $influxdb,
                'Content_Type' => 'application/x-www-form-urlencoded',
                'Content'      => $influxreq
            );
            # print $response->status_line . "\n" . $response->headers()->as_string;    # HTTP 204 is ok
        }

    }

}
