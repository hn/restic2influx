# restic2influx

Parse [Restic](https://restic.net/) status output and feed summary to influx db.

As a bonus, the program also shows the progress of the backup in the process list:
```
$ ( restic backup --json -r /path/to/backup /path/to/MyMusic | restic2influx.pl MyMusic grafana http://influxsrv:8086 ) &

$ ps auwwf | grep restic
 18:06 0:01  |  restic backup --json -r /path/to/backup /path/to/MyMusic
 18:06 0:01  |  \_ restic2influx MyMusic [Done: 53.31% ETA: 04-09 18:07 Files: 8.452 MBytes: 149]
```

## Usage

```
$ restic backup --json <restic backup options> | restic2influx.pl [-d] [-s] [-p] <restic repository> <influx db> [influx host]

-d, --debug      output debug info, do not send data to influxdb
-s, --status=N   additionally send status information to influxdb every N seconds (default 30) during the backup job
-p, --print      print summary to stdout

'influx host' defaults to http://localhost:8086 if omitted
```

## Grafana

With [Grafana](https://grafana.com/) one can realize beautiful diagrams of the data:

![Picture of an example Grafana dashboard](restic2influx-grafana.png "Grafana example dashboard")

## Credits

Forum user [griffon](https://forum.restic.net/u/griffon/) implemented a
[similar approach](https://forum.restic.net/t/restic-grafana-dashboard/1662/8) using `jq`.

