# NTP Pool Project

This is the code for the NTP Pool project, http://www.pool.ntp.org/

See the LICENSE file for detailed copyright and licensing information.

# Installation instructions

Quick and dirty install instructions; email ask@develooper.com for
help.

```sh
export DIR=`pwd`/ntppool
git clone http://github.com/abh/ntppool
cd ntppool
git submodule update --init

```

The easiest way to install Perl 5.16.x (if your system didn't come
with this) is to use [perlbrew](http://perlbrew.pl):

```sh
curl -kL http://install.perlbrew.pl | bash
perlbrew install perl-5.16.1
perlbrew use perl-5.16.1

# Other dependencies
sudo port install libgeoip

# install a bazillion modules from CPAN, use -n to not test each module,
# this will take a while.
mkdir cpan
cpanm -L cpan < .modules
```

Setup the configuration file:

```sh
cp combust/combust.conf.sample combust.conf
edit combust.conf 
   # setup the database section with an "ntppool" database
   # add "ntppool" to the "sites = ... " list.
   # setup a [ntppool] section at the bottom
```

Configure mysql and the initial tables:

```sh
# Your MySQL server needs timezone data loaded, if it doesn't have it, run:
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
mysqladmin -uroot create ntppool

$CBROOT/bin/cmysql ntppool < sql/tables.sql
$CBROOT/bin/cmysql ntppool < sql/zones.sql
$CBROOT/bin/database_update ntppool
$CBROOT/bin/database_update combust
$CBROOT/bin/database_update ntppool
```

Start the web server:

```sh
export CBROOTLOCAL=$DIR
export CBROOT=$DIR/combust

make templates

$CBROOT/bin/httpd
```

## Monitoring system

To setup a monitoring system in the 'monitors' table, run

   `./pool addmonitor email@example.com 127.0.0.1 v4`

It will return an api key to be used with the ./monitor script.


## License

* Copyright 2005-2012 Ask Bjoern Hansen, Develooper LLC
* Copyright 2003-2005 Adrian von Bidder

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
