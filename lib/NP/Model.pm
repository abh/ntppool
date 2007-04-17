package NP::Model;
##
## This file is auto-generated *** DO NOT EDIT ***
##
use Combust::RoseDB;

our $SVN = q$Id$;
our @table_classes;

{
  package NP::Model::_Meta;
  use base qw(Combust::RoseDB::Metadata);
  use NP::DB::ConventionManager;
  sub registry_key { __PACKAGE__ }
  sub init_convention_manager { NP::DB::ConventionManager->new }
}
{
  package NP::Model::_Base;
  use base qw(Combust::RoseDB::Object::toJson);

  sub init_db    { shift; our $db ||= Combust::RoseDB->new(@_, type => 'ntppool') }
  sub meta_class {'NP::Model::_Meta'}
  sub model      { our $model ||= bless [], 'NP::Model'}
}
{
  package NP::Model::_Object;
  use base qw(NP::Model::_Base Rose::DB::Object);
}
{
  package NP::Model::_Object::Cached;
  use base qw(NP::Model::_Base Rose::DB::Object::Cached);
}

# Allow user defined methods to be added
eval { require NP::Model::Log }
  or $@ !~ m:^Can't locate NP/Model/Log.pm: and die $@;

{ package NP::Model::Log;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'logs',

  columns => [
    id             => { type => 'integer', not_null => 1 },
    server_id      => { type => 'integer' },
    user_id        => { type => 'integer' },
    vendor_zone_id => { type => 'integer' },
    type           => { type => 'varchar', length => 50 },
    title          => { type => 'varchar', length => 255 },
    message        => { type => 'text', length => 65535 },
    created_on     => { type => 'datetime', default => 'now', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },

    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },

    vendor_zone => {
      class       => 'NP::Model::VendorZone',
      key_columns => { vendor_zone_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Log::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Log' }

__PACKAGE__->make_manager_methods('logs');
}


# Allow user defined methods to be added
eval { require NP::Model::LogScore }
  or $@ !~ m:^Can't locate NP/Model/LogScore.pm: and die $@;

{ package NP::Model::LogScore;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'log_scores',

  columns => [
    id        => { type => 'integer', not_null => 1 },
    server_id => { type => 'integer', default => '', not_null => 1 },
    ts        => { type => 'datetime', default => 'now', not_null => 1 },
    score     => { type => 'scalar', default => '', length => 64, not_null => 1 },
    step      => { type => 'scalar', default => '', length => 64, not_null => 1 },
    offset    => { type => 'scalar', length => 64 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::LogScore::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::LogScore' }

__PACKAGE__->make_manager_methods('log_scores');
}


# Allow user defined methods to be added
eval { require NP::Model::Server }
  or $@ !~ m:^Can't locate NP/Model/Server.pm: and die $@;

{ package NP::Model::Server;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'servers',

  columns => [
    id             => { type => 'integer', not_null => 1 },
    ip             => { type => 'varchar', default => '', length => 15, not_null => 1 },
    user_id        => { type => 'integer', default => '', not_null => 1 },
    hostname       => { type => 'varchar', length => 255 },
    stratum        => { type => 'integer' },
    in_pool        => { type => 'integer', default => '0', not_null => 1 },
    in_server_list => { type => 'integer', default => '0', not_null => 1 },
    netspeed       => { type => 'scalar', default => 1000, length => 8, not_null => 1 },
    created_on     => { type => 'datetime', default => 'now', not_null => 1 },
    updated_on     => { type => 'timestamp', not_null => 1 },
    score_ts       => { type => 'datetime' },
    score_raw      => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    deletion_on    => { type => 'date' },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'ip' ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],

  relationships => [
    log_scores => {
      class      => 'NP::Model::LogScore',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    server_alert => {
      class      => 'NP::Model::ServerAlert',
      column_map => { id => 'server_id' },
      type       => 'one to one',
    },

    server_notes => {
      class      => 'NP::Model::ServerNote',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    server_urls => {
      class      => 'NP::Model::ServerUrl',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    zones => {
      column_map    => { server_id => 'id' },
      foreign_class => 'NP::Model::Zone',
      map_class     => 'NP::Model::ServerZone',
      map_from      => 'server',
      map_to        => 'zone',
      type          => 'many to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Server::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Server' }

__PACKAGE__->make_manager_methods('servers');
}


# Allow user defined methods to be added
eval { require NP::Model::ServerAlert }
  or $@ !~ m:^Can't locate NP/Model/ServerAlert.pm: and die $@;

{ package NP::Model::ServerAlert;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_alerts',

  columns => [
    server_id        => { type => 'integer', not_null => 1 },
    last_score       => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    first_email_time => { type => 'datetime', default => 'now', not_null => 1 },
    last_email_time  => { type => 'datetime' },
  ],

  primary_key_columns => [ 'server_id' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
      rel_type    => 'one to one',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServerAlert::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerAlert' }

__PACKAGE__->make_manager_methods('server_alerts');
}


# Allow user defined methods to be added
eval { require NP::Model::ServerNote }
  or $@ !~ m:^Can't locate NP/Model/ServerNote.pm: and die $@;

{ package NP::Model::ServerNote;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_notes',

  columns => [
    id         => { type => 'integer', not_null => 1 },
    server_id  => { type => 'integer', default => '', not_null => 1 },
    name       => { type => 'varchar', default => '', length => 255, not_null => 1 },
    note       => { type => 'text', default => '', length => 65535, not_null => 1 },
    created_on => { type => 'datetime', default => 'now', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'server_id', 'name' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServerNote::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerNote' }

__PACKAGE__->make_manager_methods('server_notes');
}


# Allow user defined methods to be added
eval { require NP::Model::ServerUrl }
  or $@ !~ m:^Can't locate NP/Model/ServerUrl.pm: and die $@;

{ package NP::Model::ServerUrl;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_urls',

  columns => [
    id        => { type => 'integer', not_null => 1 },
    server_id => { type => 'integer', default => '', not_null => 1 },
    url       => { type => 'varchar', default => '', length => 255, not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServerUrl::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerUrl' }

__PACKAGE__->make_manager_methods('server_urls');
}


# Allow user defined methods to be added
eval { require NP::Model::ServerZone }
  or $@ !~ m:^Can't locate NP/Model/ServerZone.pm: and die $@;

{ package NP::Model::ServerZone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_zones',

  columns => [
    server_id => { type => 'integer', not_null => 1 },
    zone_id   => { type => 'integer', not_null => 1 },
  ],

  primary_key_columns => [ 'server_id', 'zone_id' ],

  foreign_keys => [
    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },

    zone => {
      class       => 'NP::Model::Zone',
      key_columns => { zone_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServerZone::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerZone' }

__PACKAGE__->make_manager_methods('server_zones');
}


# Allow user defined methods to be added
eval { require NP::Model::User }
  or $@ !~ m:^Can't locate NP/Model/User.pm: and die $@;

{ package NP::Model::User;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'users',

  columns => [
    id                => { type => 'integer', not_null => 1 },
    email             => { type => 'varchar', default => '', length => 255, not_null => 1 },
    name              => { type => 'varchar', length => 255 },
    pass              => { type => 'varchar', length => 255 },
    nomail            => { type => 'enum', default => '0', not_null => 1, values => [ '0', 1 ] },
    bitcard_id        => { type => 'varchar', length => 40 },
    username          => { type => 'varchar', length => 40 },
    public_profile    => { type => 'integer', default => '0', not_null => 1 },
    organization_name => { type => 'varchar', length => 150 },
    organization_url  => { type => 'varchar', length => 150 },
  ],

  primary_key_columns => [ 'id' ],

  unique_keys => [
    [ 'bitcard_id' ],
    [ 'email' ],
    [ 'username' ],
  ],

  relationships => [
    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    servers_all => {
      class      => 'NP::Model::Server',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    user_privilege => {
      class      => 'NP::Model::UserPrivilege',
      column_map => { id => 'user_id' },
      type       => 'one to one',
    },

    vendor_zones => {
      class      => 'NP::Model::VendorZone',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::User::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::User' }

__PACKAGE__->make_manager_methods('users');
}


# Allow user defined methods to be added
eval { require NP::Model::UserPrivilege }
  or $@ !~ m:^Can't locate NP/Model/UserPrivilege.pm: and die $@;

{ package NP::Model::UserPrivilege;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'user_privileges',

  columns => [
    user_id               => { type => 'integer', not_null => 1 },
    see_all_servers       => { type => 'integer', default => '0', not_null => 1 },
    see_all_user_profiles => { type => 'integer', default => '0', not_null => 1 },
  ],

  primary_key_columns => [ 'user_id' ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
      rel_type    => 'one to one',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::UserPrivilege::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::UserPrivilege' }

__PACKAGE__->make_manager_methods('user_privileges');
}


# Allow user defined methods to be added
eval { require NP::Model::VendorZone }
  or $@ !~ m:^Can't locate NP/Model/VendorZone.pm: and die $@;

{ package NP::Model::VendorZone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'vendor_zones',

  columns => [
    id                  => { type => 'integer', not_null => 1 },
    name                => { type => 'varchar', default => '', length => 255, not_null => 1 },
    user_id             => { type => 'integer' },
    vendor_cluster      => { type => 'integer', default => '0', not_null => 1 },
    description         => { type => 'varchar', length => 255 },
    contact_information => { type => 'text', length => 65535 },
    request_information => { type => 'text', length => 65535 },
    devices             => { type => 'integer' },
    rt_ticket           => { type => 'integer' },
    approved_on         => { type => 'datetime' },
    created_on          => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on         => { type => 'timestamp', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'name' ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],

  relationships => [
    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'vendor_zone_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::VendorZone::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::VendorZone' }

__PACKAGE__->make_manager_methods('vendor_zones');
}


# Allow user defined methods to be added
eval { require NP::Model::Zone }
  or $@ !~ m:^Can't locate NP/Model/Zone.pm: and die $@;

{ package NP::Model::Zone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'zones',

  columns => [
    id          => { type => 'integer', not_null => 1 },
    name        => { type => 'varchar', default => '', length => 255, not_null => 1 },
    description => { type => 'varchar', length => 255 },
    parent_id   => { type => 'integer' },
    dns         => { type => 'integer', default => 1, not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'name' ],

  foreign_keys => [
    parent => {
      class       => 'NP::Model::Zone',
      key_columns => { parent_id => 'id' },
    },
  ],

  relationships => [
    servers => {
      column_map    => { zone_id => 'id' },
      foreign_class => 'NP::Model::Server',
      map_class     => 'NP::Model::ServerZone',
      map_from      => 'zone',
      map_to        => 'server',
      type          => 'many to many',
    },

    zone_server_counts => {
      class      => 'NP::Model::ZoneServerCount',
      column_map => { id => 'zone_id' },
      type       => 'one to many',
    },

    zones => {
      class      => 'NP::Model::Zone',
      column_map => { id => 'parent_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Zone::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Zone' }

__PACKAGE__->make_manager_methods('zones');
}


# Allow user defined methods to be added
eval { require NP::Model::ZoneServerCount }
  or $@ !~ m:^Can't locate NP/Model/ZoneServerCount.pm: and die $@;

{ package NP::Model::ZoneServerCount;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'zone_server_counts',

  columns => [
    id               => { type => 'integer', not_null => 1 },
    zone_id          => { type => 'integer', default => '', not_null => 1 },
    date             => { type => 'date', default => '', not_null => 1 },
    count_active     => { type => 'scalar', default => '', length => 8, not_null => 1 },
    count_registered => { type => 'scalar', default => '', length => 8, not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'zone_id', 'date' ],

  foreign_keys => [
    zone => {
      class       => 'NP::Model::Zone',
      key_columns => { zone_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ZoneServerCount::Manager;

use Combust::RoseDB::Manager;
our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ZoneServerCount' }

__PACKAGE__->make_manager_methods('zone_server_counts');
}

{ package NP::Model;

  sub db  { shift; NP::Model::_Object->init_db(@_);      }
  sub dbh { shift->db->dbh; }

  sub flush_caches {
    $_->meta->clear_object_cache for @table_classes;
  }

  sub log { our $log ||= bless [], 'NP::Model::Log::Manager' }
  sub log_score { our $log_score ||= bless [], 'NP::Model::LogScore::Manager' }
  sub server { our $server ||= bless [], 'NP::Model::Server::Manager' }
  sub server_alert { our $server_alert ||= bless [], 'NP::Model::ServerAlert::Manager' }
  sub server_note { our $server_note ||= bless [], 'NP::Model::ServerNote::Manager' }
  sub server_url { our $server_url ||= bless [], 'NP::Model::ServerUrl::Manager' }
  sub server_zone { our $server_zone ||= bless [], 'NP::Model::ServerZone::Manager' }
  sub user { our $user ||= bless [], 'NP::Model::User::Manager' }
  sub user_privilege { our $user_privilege ||= bless [], 'NP::Model::UserPrivilege::Manager' }
  sub vendor_zone { our $vendor_zone ||= bless [], 'NP::Model::VendorZone::Manager' }
  sub zone { our $zone ||= bless [], 'NP::Model::Zone::Manager' }
  sub zone_server_count { our $zone_server_count ||= bless [], 'NP::Model::ZoneServerCount::Manager' }

}
1;
