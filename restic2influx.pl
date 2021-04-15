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
use Getopt::Long;

my $debug;
my $print;
my $status;
my $repo;
my $influxdb;
my $influxhost = 'http://localhost:8086';

my $start = time();
my $lastreq;

GetOptions ("debug|d "    => \$debug,
            "print|p"     => \$print,
            "status|s:30" => \$status,
            "debug"       => \$debug
            ) || die( "Error in command line arguments\n" );

$repo = shift(@ARGV);
$influxdb = shift(@ARGV);
$influxhost = shift(@ARGV) if (@ARGV);

die("Usage: $0 [-d] [-s] [-p] <restic repository> <influx db> [influx host]") if ( !$repo || !$influxdb);

while ( my $line = <STDIN> ) {

    # {"message_type":"status","seconds_elapsed":2,"percent_done":0.5780588424279393,"total_files":8864,
    #  "files_done":2737,"total_bytes":157955039,"bytes_done":91307307}
    #
    # {"message_type":"summary","files_new":0,"files_changed":0,"files_unmodified":8864,"dirs_new":0,
    #  "dirs_changed":0,"dirs_unmodified":986,"data_blobs":0,"tree_blobs":0,"data_added":0,"total_files_processed":8864,
    #  "total_bytes_processed":157955039,"total_duration":3.742542353,"snapshot_id":"51a48509"}

    my $now = time();
    my $message;
    eval { $message = decode_json($line); 1; } || next;

    my $type = delete ${$message}{'message_type'};
    my $influxreq;

    if ( $type eq "status" ) {
        my $total_files = $message->{"total_files"};
        while ( $total_files =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { };   # add thousands separator
        my $files_done = $message->{"files_done"} || 0;
        while ( $files_done =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { };
        my $total_mbytes = int ( $message->{"total_bytes"} / 1048576 );
        while ( $total_mbytes =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { }
        my $mbytes_done = int ( $message->{"bytes_done"} / 1048576 );
        while ( $mbytes_done =~ s/(\d+)(\d\d\d)/$1\.$2/ ) { }
        my $percent = $message->{"percent_done"};
        my $elapsed = $message->{"seconds_elapsed"};
        $0 = "restic2influx " . $repo
          . " [Done: " . sprintf( "%.2f%%", $percent * 100 )
          . " ETA: " . ( ( $percent > 0 ) ? strftime "%m-%d %H:%M", localtime( $now - $elapsed + ( $elapsed / $percent ) ) : "unknown" )
          . " Files: " . $files_done . "/" . $total_files
          . " MBytes: " . $mbytes_done . "/" . $total_mbytes . "]";

        if ($status && (($now - $lastreq) > $status)) {
            $lastreq = $now;
            $message->{"percent_done"} .= ".0" unless ($message->{"percent_done"} =~ /\./);	# force float
            $influxreq = data2line(
                'restic',
                $message,
                { 'repo' => $repo, 'type' => $type }
            );
        }

    } elsif ( $type eq "summary" ) {
        foreach my $key ( sort keys %{$message} ) {
            printf "%23s: %s\n", $key, $message->{$key} if ($print);
        }
        my $snapshot = delete ${$message}{'snapshot_id'};
        $influxreq = data2line(
            'restic',
            $message,
            { 'repo' => $repo, 'type' => $type, 'snapshot' => $snapshot }
        );
    }

    next unless ($influxreq);

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
