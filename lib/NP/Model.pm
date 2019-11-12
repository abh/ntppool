package NP::Model;
##
## This file is auto-generated *** DO NOT EDIT ***
##
use Combust::RoseDB;
use Combust::RoseDB::Manager;

our @table_classes;

BEGIN {
  package NP::Model::_Meta;
  use base qw(Combust::RoseDB::Metadata);
  use NP::DB::ConventionManager;
  our $VERSION = 0;

  sub registry_key { __PACKAGE__ }
  sub init_convention_manager { NP::DB::ConventionManager->new }
}
BEGIN {
  package NP::Model::_Base;
  use base qw(Combust::RoseDB::Object Combust::RoseDB::Object::toJson);
  our $VERSION = 0;

  sub init_db       { shift; Combust::RoseDB->new_or_cached(@_, type => 'ntppool', combust_model => "NP::Model") }
  sub meta_class    {'NP::Model::_Meta'}
  sub combust_model { our $model ||= bless [], 'NP::Model'}
}
BEGIN {
  package NP::Model::_Object;
  use base qw(NP::Model::_Base Rose::DB::Object);
  our $VERSION = 0;
}
BEGIN {
  package NP::Model::_Object::Cached;
  use base qw(NP::Model::_Base Rose::DB::Object::Cached);
  our $VERSION = 0;
}

{ package NP::Model::Account;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'accounts',

  columns => [
    id                => { type => 'serial', not_null => 1 },
    name              => { type => 'varchar', length => 255 },
    account_plan_id   => { type => 'integer' },
    organization_name => { type => 'varchar', length => 150 },
    organization_url  => { type => 'varchar', length => 150 },
    public_profile    => { type => 'integer', default => '0', not_null => 1 },
    url_slug          => { type => 'varchar', length => 150 },
    created_on        => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on       => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'url_slug' ],

  allow_inline_column_values => 1,

  foreign_keys => [
    account_plan => {
      class       => 'NP::Model::AccountPlan',
      key_columns => { account_plan_id => 'id' },
    },
  ],

  relationships => [
    invites => {
      class      => 'NP::Model::AccountInvite',
      column_map => { id => 'account_id' },
      type       => 'one to many',
    },

    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'account_id' },
      type       => 'one to many',
    },

    servers_all => {
      class      => 'NP::Model::Server',
      column_map => { id => 'account_id' },
      type       => 'one to many',
    },

    users => {
      map_class => 'NP::Model::AccountUser',
      map_from  => 'account',
      map_to    => 'user',
      type      => 'many to many',
    },

    vendor_zones => {
      class      => 'NP::Model::VendorZone',
      column_map => { id => 'account_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Account::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Account' }

__PACKAGE__->make_manager_methods('accounts');
}

# Allow user defined methods to be added
eval { require NP::Model::Account }
  or $@ !~ m:^Can't locate NP/Model/Account.pm: and die $@;

{ package NP::Model::AccountInvite;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'account_invites',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    account_id  => { type => 'integer', not_null => 1 },
    email       => { type => 'varchar', length => 255, not_null => 1 },
    status      => { type => 'enum', check_in => [ 'pending', 'accepted', 'expired' ] },
    user_id     => { type => 'integer' },
    sent_by_id  => { type => 'integer', not_null => 1 },
    code        => { type => 'varchar', length => 25, not_null => 1 },
    expires_on  => { type => 'datetime', default => 'now', not_null => 1 },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_keys => [
    [ 'account_id', 'email' ],
    [ 'code' ],
  ],

  allow_inline_column_values => 1,

  foreign_keys => [
    account => {
      class       => 'NP::Model::Account',
      key_columns => { account_id => 'id' },
    },

    sent_by => {
      class       => 'NP::Model::User',
      key_columns => { sent_by_id => 'id' },
    },

    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::AccountInvite::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::AccountInvite' }

__PACKAGE__->make_manager_methods('account_invites');
}

# Allow user defined methods to be added
eval { require NP::Model::AccountInvite }
  or $@ !~ m:^Can't locate NP/Model/AccountInvite.pm: and die $@;

{ package NP::Model::AccountPlan;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'account_plans',

  columns => [
    id        => { type => 'serial', not_null => 1 },
    plan_type => { type => 'varchar', length => 255 },
    plan_key  => { type => 'varchar', length => 255 },
  ],

  primary_key_columns => [ 'id' ],

  relationships => [
    accounts => {
      class      => 'NP::Model::Account',
      column_map => { id => 'account_plan_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::AccountPlan::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::AccountPlan' }

__PACKAGE__->make_manager_methods('account_plans');
}

# Allow user defined methods to be added
eval { require NP::Model::AccountPlan }
  or $@ !~ m:^Can't locate NP/Model/AccountPlan.pm: and die $@;

{ package NP::Model::AccountUser;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'account_users',

  columns => [
    account_id => { type => 'integer', not_null => 1 },
    user_id    => { type => 'integer', not_null => 1 },
  ],

  primary_key_columns => [ 'account_id', 'user_id' ],

  foreign_keys => [
    account => {
      class       => 'NP::Model::Account',
      key_columns => { account_id => 'id' },
    },

    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::AccountUser::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::AccountUser' }

__PACKAGE__->make_manager_methods('account_users');
}

# Allow user defined methods to be added
eval { require NP::Model::AccountUser }
  or $@ !~ m:^Can't locate NP/Model/AccountUser.pm: and die $@;

{ package NP::Model::ApiKey;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'api_keys',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    api_key     => { type => 'varchar', length => 255 },
    grants      => { type => 'text', length => 65535 },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'api_key' ],

  allow_inline_column_values => 1,
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ApiKey::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ApiKey' }

__PACKAGE__->make_manager_methods('api_keies');
}

# Allow user defined methods to be added
eval { require NP::Model::ApiKey }
  or $@ !~ m:^Can't locate NP/Model/ApiKey.pm: and die $@;

{ package NP::Model::DnsRoot;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'dns_roots',

  columns => [
    id               => { type => 'serial', not_null => 1 },
    origin           => { type => 'varchar', length => 255, not_null => 1 },
    vendor_available => { type => 'integer', default => '0', not_null => 1 },
    general_use      => { type => 'integer', default => '0', not_null => 1 },
    ns_list          => { type => 'varchar', length => 255, not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'origin' ],

  relationships => [
    vendor_zones => {
      class      => 'NP::Model::VendorZone',
      column_map => { id => 'dns_root_id' },
      type       => 'one to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::DnsRoot::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::DnsRoot' }

__PACKAGE__->make_manager_methods('dns_roots');
}

# Allow user defined methods to be added
eval { require NP::Model::DnsRoot }
  or $@ !~ m:^Can't locate NP/Model/DnsRoot.pm: and die $@;

{ package NP::Model::Log;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'logs',

  columns => [
    id             => { type => 'serial', not_null => 1 },
    account_id     => { type => 'integer' },
    server_id      => { type => 'integer' },
    user_id        => { type => 'integer' },
    vendor_zone_id => { type => 'integer' },
    type           => { type => 'varchar', length => 50 },
    message        => { type => 'text', length => 65535 },
    changes        => { type => 'text', length => 65535 },
    created_on     => { type => 'datetime', default => 'now', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    account => {
      class       => 'NP::Model::Account',
      key_columns => { account_id => 'id' },
    },

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

__PACKAGE__->meta->setup_json_columns(qw< changes >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Log::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Log' }

__PACKAGE__->make_manager_methods('logs');
}

# Allow user defined methods to be added
eval { require NP::Model::Log }
  or $@ !~ m:^Can't locate NP/Model/Log.pm: and die $@;

{ package NP::Model::LogScore;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'log_scores',

  columns => [
    id         => { type => 'bigserial', not_null => 1 },
    monitor_id => { type => 'integer' },
    server_id  => { type => 'integer', not_null => 1 },
    ts         => { type => 'datetime', default => 'now', not_null => 1 },
    score      => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    step       => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    offset     => { type => 'scalar', length => 64 },
    attributes => { type => 'text', length => 65535 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    monitor => {
      class       => 'NP::Model::Monitor',
      key_columns => { monitor_id => 'id' },
    },

    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },
  ],
);

__PACKAGE__->meta->setup_json_columns(qw< attributes >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::LogScore::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::LogScore' }

__PACKAGE__->make_manager_methods('log_scores');
}

# Allow user defined methods to be added
eval { require NP::Model::LogScore }
  or $@ !~ m:^Can't locate NP/Model/LogScore.pm: and die $@;

{ package NP::Model::LogStatus;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'log_status',

  columns => [
    server_id   => { type => 'integer', not_null => 1 },
    last_check  => { type => 'datetime', default => 'now', not_null => 1 },
    ts_archived => { type => 'datetime', default => 'now', not_null => 1 },
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

{ package NP::Model::LogStatus::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::LogStatus' }

__PACKAGE__->make_manager_methods('log_status');
}

# Allow user defined methods to be added
eval { require NP::Model::LogStatus }
  or $@ !~ m:^Can't locate NP/Model/LogStatus.pm: and die $@;

{ package NP::Model::Monitor;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'monitors',

  columns => [
    id         => { type => 'serial', not_null => 1 },
    user_id    => { type => 'integer' },
    name       => { type => 'varchar', length => 30, not_null => 1 },
    ip         => { type => 'varchar', length => 40, not_null => 1 },
    ip_version => { type => 'enum', check_in => [ 'v4', 'v6' ], not_null => 1 },
    api_key    => { type => 'varchar', length => 40, not_null => 1 },
    config     => { type => 'text', length => 65535, not_null => 1 },
    last_seen  => { type => 'datetime' },
    created_on => { type => 'datetime', default => 'now', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_keys => [
    [ 'api_key' ],
    [ 'ip', 'ip_version' ],
  ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],

  relationships => [
    log_scores => {
      class      => 'NP::Model::LogScore',
      column_map => { id => 'monitor_id' },
      type       => 'one to many',
    },

    server_scores => {
      class      => 'NP::Model::ServerScore',
      column_map => { id => 'monitor_id' },
      type       => 'one to many',
    },
  ],
);

__PACKAGE__->meta->setup_json_columns(qw< config >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Monitor::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Monitor' }

__PACKAGE__->make_manager_methods('monitors');
}

# Allow user defined methods to be added
eval { require NP::Model::Monitor }
  or $@ !~ m:^Can't locate NP/Model/Monitor.pm: and die $@;

{ package NP::Model::SchemaRevision;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'schema_revision',

  columns => [
    revision    => { type => 'integer', default => '0', not_null => 1 },
    schema_name => { type => 'varchar', length => 30, not_null => 1 },
  ],

  primary_key_columns => [ 'schema_name' ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::SchemaRevision::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::SchemaRevision' }

__PACKAGE__->make_manager_methods('schema_revisions');
}

# Allow user defined methods to be added
eval { require NP::Model::SchemaRevision }
  or $@ !~ m:^Can't locate NP/Model/SchemaRevision.pm: and die $@;

{ package NP::Model::Server;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'servers',

  columns => [
    id             => { type => 'serial', not_null => 1 },
    ip             => { type => 'varchar', length => 40, not_null => 1 },
    ip_version     => { type => 'enum', check_in => [ 'v4', 'v6' ], default => 'v4', not_null => 1 },
    user_id        => { type => 'integer', not_null => 1 },
    account_id     => { type => 'integer' },
    hostname       => { type => 'varchar', length => 255 },
    stratum        => { type => 'integer' },
    in_pool        => { type => 'integer', default => '0', not_null => 1 },
    in_server_list => { type => 'integer', default => '0', not_null => 1 },
    netspeed       => { type => 'integer', default => 1000, not_null => 1 },
    created_on     => { type => 'datetime', default => 'now', not_null => 1 },
    updated_on     => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
    score_ts       => { type => 'datetime' },
    score_raw      => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    deletion_on    => { type => 'date' },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'ip' ],

  allow_inline_column_values => 1,

  foreign_keys => [
    account => {
      class       => 'NP::Model::Account',
      key_columns => { account_id => 'id' },
    },

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

    log_status => {
      class                => 'NP::Model::LogStatus',
      column_map           => { id => 'server_id' },
      type                 => 'one to one',
      with_column_triggers => '0',
    },

    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    server_alert => {
      class                => 'NP::Model::ServerAlert',
      column_map           => { id => 'server_id' },
      type                 => 'one to one',
      with_column_triggers => '0',
    },

    server_notes => {
      class      => 'NP::Model::ServerNote',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    server_scores => {
      class      => 'NP::Model::ServerScore',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    server_urls => {
      class      => 'NP::Model::ServerUrl',
      column_map => { id => 'server_id' },
      type       => 'one to many',
    },

    zones => {
      map_class => 'NP::Model::ServerZone',
      map_from  => 'server',
      map_to    => 'zone',
      type      => 'many to many',
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::Server::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Server' }

__PACKAGE__->make_manager_methods('servers');
}

# Allow user defined methods to be added
eval { require NP::Model::Server }
  or $@ !~ m:^Can't locate NP/Model/Server.pm: and die $@;

{ package NP::Model::ServerAlert;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_alerts',

  columns => [
    server_id        => { type => 'integer', not_null => 1 },
    last_score       => { type => 'scalar', length => 64, not_null => 1 },
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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerAlert' }

__PACKAGE__->make_manager_methods('server_alerts');
}

# Allow user defined methods to be added
eval { require NP::Model::ServerAlert }
  or $@ !~ m:^Can't locate NP/Model/ServerAlert.pm: and die $@;

{ package NP::Model::ServerNote;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_notes',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    server_id   => { type => 'integer', not_null => 1 },
    name        => { type => 'varchar', default => '', length => 255, not_null => 1 },
    note        => { type => 'text', length => 65535, not_null => 1 },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'server_id', 'name' ],

  allow_inline_column_values => 1,

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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerNote' }

__PACKAGE__->make_manager_methods('server_notes');
}

# Allow user defined methods to be added
eval { require NP::Model::ServerNote }
  or $@ !~ m:^Can't locate NP/Model/ServerNote.pm: and die $@;

{ package NP::Model::ServerScore;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_scores',

  columns => [
    id          => { type => 'bigserial', not_null => 1 },
    monitor_id  => { type => 'integer', not_null => 1 },
    server_id   => { type => 'integer', not_null => 1 },
    score_ts    => { type => 'datetime' },
    score_raw   => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    stratum     => { type => 'integer' },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'server_id', 'monitor_id' ],

  allow_inline_column_values => 1,

  foreign_keys => [
    monitor => {
      class       => 'NP::Model::Monitor',
      key_columns => { monitor_id => 'id' },
    },

    server => {
      class       => 'NP::Model::Server',
      key_columns => { server_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServerScore::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerScore' }

__PACKAGE__->make_manager_methods('server_scores');
}

# Allow user defined methods to be added
eval { require NP::Model::ServerScore }
  or $@ !~ m:^Can't locate NP/Model/ServerScore.pm: and die $@;

{ package NP::Model::ServerUrl;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_urls',

  columns => [
    id        => { type => 'serial', not_null => 1 },
    server_id => { type => 'integer', not_null => 1 },
    url       => { type => 'varchar', length => 255, not_null => 1 },
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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerUrl' }

__PACKAGE__->make_manager_methods('server_urls');
}

# Allow user defined methods to be added
eval { require NP::Model::ServerUrl }
  or $@ !~ m:^Can't locate NP/Model/ServerUrl.pm: and die $@;

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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServerZone' }

__PACKAGE__->make_manager_methods('server_zones');
}

# Allow user defined methods to be added
eval { require NP::Model::ServerZone }
  or $@ !~ m:^Can't locate NP/Model/ServerZone.pm: and die $@;

{ package NP::Model::SystemSetting;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'system_settings',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    key         => { type => 'varchar', length => 255 },
    value       => { type => 'text', length => 65535 },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'key' ],

  allow_inline_column_values => 1,
);

__PACKAGE__->meta->setup_json_columns(qw< value >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::SystemSetting::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::SystemSetting' }

__PACKAGE__->make_manager_methods('system_settings');
}

# Allow user defined methods to be added
eval { require NP::Model::SystemSetting }
  or $@ !~ m:^Can't locate NP/Model/SystemSetting.pm: and die $@;

{ package NP::Model::User;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'users',

  columns => [
    id             => { type => 'serial', not_null => 1 },
    email          => { type => 'varchar', length => 255, not_null => 1 },
    name           => { type => 'varchar', length => 255 },
    username       => { type => 'varchar', length => 40 },
    public_profile => { type => 'integer', default => '0', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_keys => [
    [ 'email' ],
    [ 'username' ],
  ],

  relationships => [
    account_invites => {
      class      => 'NP::Model::AccountInvite',
      column_map => { id => 'sent_by_id' },
      type       => 'one to many',
    },

    account_invites_objs => {
      class      => 'NP::Model::AccountInvite',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    accounts => {
      map_class => 'NP::Model::AccountUser',
      map_from  => 'user',
      map_to    => 'account',
      type      => 'many to many',
    },

    logs => {
      class      => 'NP::Model::Log',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    monitors => {
      class      => 'NP::Model::Monitor',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    servers => {
      class      => 'NP::Model::Server',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    user_equipment_applications => {
      class      => 'NP::Model::UserEquipmentApplication',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    user_identities => {
      class      => 'NP::Model::UserIdentity',
      column_map => { id => 'user_id' },
      type       => 'one to many',
    },

    user_privilege => {
      class                => 'NP::Model::UserPrivilege',
      column_map           => { id => 'user_id' },
      type                 => 'one to one',
      with_column_triggers => '0',
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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::User' }

__PACKAGE__->make_manager_methods('users');
}

# Allow user defined methods to be added
eval { require NP::Model::User }
  or $@ !~ m:^Can't locate NP/Model/User.pm: and die $@;

{ package NP::Model::UserEquipmentApplication;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'user_equipment_applications',

  columns => [
    id                  => { type => 'serial', not_null => 1 },
    user_id             => { type => 'integer', not_null => 1 },
    application         => { type => 'text', length => 65535 },
    contact_information => { type => 'text', length => 65535 },
    status              => { type => 'enum', check_in => [ 'New', 'Pending', 'Maybe', 'No', 'Approved' ], default => 'New', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::UserEquipmentApplication::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::UserEquipmentApplication' }

__PACKAGE__->make_manager_methods('user_equipment_applications');
}

# Allow user defined methods to be added
eval { require NP::Model::UserEquipmentApplication }
  or $@ !~ m:^Can't locate NP/Model/UserEquipmentApplication.pm: and die $@;

{ package NP::Model::UserIdentity;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'user_identities',

  columns => [
    id         => { type => 'serial', not_null => 1 },
    profile_id => { type => 'varchar', length => 255, not_null => 1 },
    user_id    => { type => 'integer', not_null => 1 },
    provider   => { type => 'varchar', length => 255, not_null => 1 },
    data       => { type => 'text', length => 65535 },
    email      => { type => 'varchar', length => 255 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'profile_id' ],

  foreign_keys => [
    user => {
      class       => 'NP::Model::User',
      key_columns => { user_id => 'id' },
    },
  ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::UserIdentity::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::UserIdentity' }

__PACKAGE__->make_manager_methods('user_identities');
}

# Allow user defined methods to be added
eval { require NP::Model::UserIdentity }
  or $@ !~ m:^Can't locate NP/Model/UserIdentity.pm: and die $@;

{ package NP::Model::UserPrivilege;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'user_privileges',

  columns => [
    user_id               => { type => 'integer', not_null => 1 },
    see_all_servers       => { type => 'integer', default => '0', not_null => 1 },
    see_all_user_profiles => { type => 'integer', default => '0', not_null => 1 },
    vendor_admin          => { type => 'integer', default => '0', not_null => 1 },
    equipment_admin       => { type => 'integer', default => '0', not_null => 1 },
    support_staff         => { type => 'integer', default => '0', not_null => 1 },
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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::UserPrivilege' }

__PACKAGE__->make_manager_methods('user_privileges');
}

# Allow user defined methods to be added
eval { require NP::Model::UserPrivilege }
  or $@ !~ m:^Can't locate NP/Model/UserPrivilege.pm: and die $@;

{ package NP::Model::VendorZone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'vendor_zones',

  columns => [
    id                  => { type => 'serial', not_null => 1 },
    zone_name           => { type => 'varchar', length => 90, not_null => 1 },
    status              => { type => 'enum', check_in => [ 'New', 'Pending', 'Approved', 'Rejected' ], default => 'New', not_null => 1 },
    user_id             => { type => 'integer' },
    organization_name   => { type => 'varchar', length => 255 },
    client_type         => { type => 'enum', check_in => [ 'ntp', 'sntp', 'all' ], default => 'ntp', not_null => 1 },
    contact_information => { type => 'text', length => 65535 },
    request_information => { type => 'text', length => 65535 },
    device_count        => { type => 'integer' },
    rt_ticket           => { type => 'integer' },
    approved_on         => { type => 'datetime' },
    created_on          => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on         => { type => 'timestamp', default => 'current_timestamp()', not_null => 1 },
    dns_root_id         => { type => 'integer', not_null => 1 },
    account_id          => { type => 'integer' },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'zone_name', 'dns_root_id' ],

  allow_inline_column_values => 1,

  foreign_keys => [
    account => {
      class       => 'NP::Model::Account',
      key_columns => { account_id => 'id' },
    },

    dns_root => {
      class       => 'NP::Model::DnsRoot',
      key_columns => { dns_root_id => 'id' },
    },

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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::VendorZone' }

__PACKAGE__->make_manager_methods('vendor_zones');
}

# Allow user defined methods to be added
eval { require NP::Model::VendorZone }
  or $@ !~ m:^Can't locate NP/Model/VendorZone.pm: and die $@;

{ package NP::Model::Zone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'zones',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    name        => { type => 'varchar', length => 255, not_null => 1 },
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
      map_class => 'NP::Model::ServerZone',
      map_from  => 'zone',
      map_to    => 'server',
      type      => 'many to many',
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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::Zone' }

__PACKAGE__->make_manager_methods('zones');
}

# Allow user defined methods to be added
eval { require NP::Model::Zone }
  or $@ !~ m:^Can't locate NP/Model/Zone.pm: and die $@;

{ package NP::Model::ZoneServerCount;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'zone_server_counts',

  columns => [
    id               => { type => 'serial', not_null => 1 },
    zone_id          => { type => 'integer', not_null => 1 },
    ip_version       => { type => 'enum', check_in => [ 'v4', 'v6' ], not_null => 1 },
    date             => { type => 'date', not_null => 1 },
    count_active     => { type => 'integer', not_null => 1 },
    count_registered => { type => 'integer', not_null => 1 },
    netspeed_active  => { type => 'integer', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'zone_id', 'date', 'ip_version' ],

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

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ZoneServerCount' }

__PACKAGE__->make_manager_methods('zone_server_counts');
}

# Allow user defined methods to be added
eval { require NP::Model::ZoneServerCount }
  or $@ !~ m:^Can't locate NP/Model/ZoneServerCount.pm: and die $@;
{ package NP::Model;

  sub db  { shift; NP::Model::_Object->init_db(@_);      }
  sub dbh { shift->db->dbh; }

  my @cache_classes = grep { $_->can('clear_object_cache') } @table_classes;
  sub flush_caches {
    $_->clear_object_cache for @cache_classes;
  }

  sub account { our $account ||= bless [], 'NP::Model::Account::Manager' }
  sub account_invite { our $account_invite ||= bless [], 'NP::Model::AccountInvite::Manager' }
  sub account_plan { our $account_plan ||= bless [], 'NP::Model::AccountPlan::Manager' }
  sub account_user { our $account_user ||= bless [], 'NP::Model::AccountUser::Manager' }
  sub api_key { our $api_key ||= bless [], 'NP::Model::ApiKey::Manager' }
  sub dns_root { our $dns_root ||= bless [], 'NP::Model::DnsRoot::Manager' }
  sub log { our $log ||= bless [], 'NP::Model::Log::Manager' }
  sub log_score { our $log_score ||= bless [], 'NP::Model::LogScore::Manager' }
  sub log_status { our $log_status ||= bless [], 'NP::Model::LogStatus::Manager' }
  sub monitor { our $monitor ||= bless [], 'NP::Model::Monitor::Manager' }
  sub schema_revision { our $schema_revision ||= bless [], 'NP::Model::SchemaRevision::Manager' }
  sub server { our $server ||= bless [], 'NP::Model::Server::Manager' }
  sub server_alert { our $server_alert ||= bless [], 'NP::Model::ServerAlert::Manager' }
  sub server_note { our $server_note ||= bless [], 'NP::Model::ServerNote::Manager' }
  sub server_score { our $server_score ||= bless [], 'NP::Model::ServerScore::Manager' }
  sub server_url { our $server_url ||= bless [], 'NP::Model::ServerUrl::Manager' }
  sub server_zone { our $server_zone ||= bless [], 'NP::Model::ServerZone::Manager' }
  sub system_setting { our $system_setting ||= bless [], 'NP::Model::SystemSetting::Manager' }
  sub user { our $user ||= bless [], 'NP::Model::User::Manager' }
  sub user_equipment_application { our $user_equipment_application ||= bless [], 'NP::Model::UserEquipmentApplication::Manager' }
  sub user_identity { our $user_identity ||= bless [], 'NP::Model::UserIdentity::Manager' }
  sub user_privilege { our $user_privilege ||= bless [], 'NP::Model::UserPrivilege::Manager' }
  sub vendor_zone { our $vendor_zone ||= bless [], 'NP::Model::VendorZone::Manager' }
  sub zone { our $zone ||= bless [], 'NP::Model::Zone::Manager' }
  sub zone_server_count { our $zone_server_count ||= bless [], 'NP::Model::ZoneServerCount::Manager' }

}
1;
