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

{ package NP::Model::AccountSubscription;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'account_subscriptions',

  columns => [
    id                     => { type => 'serial', not_null => 1 },
    account_id             => { type => 'integer', not_null => 1 },
    stripe_subscription_id => { type => 'varchar', length => 255 },
    status                 => { type => 'enum', check_in => [ 'incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'ended' ] },
    name                   => { type => 'varchar', length => 255, not_null => 1 },
    max_zones              => { type => 'integer', not_null => 1 },
    max_devices            => { type => 'integer', not_null => 1 },
    created_on             => { type => 'datetime', default => 'now', not_null => 1 },
    ended_on               => { type => 'datetime' },
    modified_on            => { type => 'timestamp', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'stripe_subscription_id' ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::AccountSubscription::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::AccountSubscription' }

__PACKAGE__->make_manager_methods('account_subscriptions');
}

# Allow user defined methods to be added
eval { require NP::Model::AccountSubscription }
  or $@ !~ m:^Can't locate NP/Model/AccountSubscription.pm: and die $@;

{ package NP::Model::OidcPublicKey;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'oidc_public_keys',

  columns => [
    id         => { type => 'bigserial', not_null => 1 },
    kid        => { type => 'varchar', length => 255, not_null => 1 },
    public_key => { type => 'text', length => 65535, not_null => 1 },
    algorithm  => { type => 'varchar', length => 20, not_null => 1 },
    created_at => { type => 'timestamp', not_null => 1 },
    expires_at => { type => 'timestamp' },
    active     => { type => 'integer', default => 1, not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'kid' ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::OidcPublicKey::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::OidcPublicKey' }

__PACKAGE__->make_manager_methods('oidc_public_keies');
}

# Allow user defined methods to be added
eval { require NP::Model::OidcPublicKey }
  or $@ !~ m:^Can't locate NP/Model/OidcPublicKey.pm: and die $@;

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

{ package NP::Model::ScorerStatu;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'scorer_status',

  columns => [
    id           => { type => 'serial', not_null => 1 },
    scorer_id    => { type => 'integer', not_null => 1 },
    log_score_id => { type => 'bigint', not_null => 1 },
    modified_on  => { type => 'timestamp', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],
);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ScorerStatu::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ScorerStatu' }

__PACKAGE__->make_manager_methods('scorer_status');
}

# Allow user defined methods to be added
eval { require NP::Model::ScorerStatu }
  or $@ !~ m:^Can't locate NP/Model/ScorerStatu.pm: and die $@;

{ package NP::Model::ServerScore;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'server_scores',

  columns => [
    id                         => { type => 'bigserial', not_null => 1 },
    monitor_id                 => { type => 'integer', not_null => 1 },
    server_id                  => { type => 'integer', not_null => 1 },
    score_ts                   => { type => 'datetime' },
    score_raw                  => { type => 'scalar', default => '0', length => 64, not_null => 1 },
    stratum                    => { type => 'integer' },
    status                     => { type => 'enum', check_in => [ 'candidate', 'testing', 'active', 'paused' ], default => 'candidate', not_null => 1 },
    queue_ts                   => { type => 'datetime' },
    created_on                 => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on                => { type => 'timestamp', not_null => 1 },
    constraint_violation_type  => { type => 'varchar', length => 50 },
    constraint_violation_since => { type => 'datetime' },
    last_constraint_check      => { type => 'datetime' },
    pause_reason               => { type => 'varchar', length => 20 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'server_id', 'monitor_id' ],
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

{ package NP::Model::ServersMonitorReview;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'servers_monitor_review',

  columns => [
    server_id   => { type => 'integer', not_null => 1 },
    last_review => { type => 'datetime' },
    next_review => { type => 'datetime' },
    last_change => { type => 'datetime' },
    config      => { type => 'varchar', default => '', length => 4096, not_null => 1 },
  ],

  primary_key_columns => [ 'server_id' ],
);

__PACKAGE__->meta->setup_json_columns(qw< config >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::ServersMonitorReview::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::ServersMonitorReview' }

__PACKAGE__->make_manager_methods('servers_monitor_reviews');
}

# Allow user defined methods to be added
eval { require NP::Model::ServersMonitorReview }
  or $@ !~ m:^Can't locate NP/Model/ServersMonitorReview.pm: and die $@;

{ package NP::Model::SystemSetting;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'system_settings',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    key         => { type => 'varchar', length => 255, not_null => 1 },
    value       => { type => 'text', length => 65535, not_null => 1 },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'key' ],
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

{ package NP::Model::UserTask;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'user_tasks',

  columns => [
    id          => { type => 'serial', not_null => 1 },
    user_id     => { type => 'integer' },
    task        => { type => 'enum', check_in => [ 'download', 'delete' ], not_null => 1 },
    status      => { type => 'text', length => 65535, not_null => 1 },
    traceid     => { type => 'varchar', default => '', length => 32, not_null => 1 },
    execute_on  => { type => 'datetime' },
    created_on  => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on => { type => 'timestamp', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],
);

__PACKAGE__->meta->setup_json_columns(qw< status >);

push @table_classes, __PACKAGE__;
}

{ package NP::Model::UserTask::Manager;

use strict;

our @ISA = qw(Combust::RoseDB::Manager);

sub object_class { 'NP::Model::UserTask' }

__PACKAGE__->make_manager_methods('user_tasks');
}

# Allow user defined methods to be added
eval { require NP::Model::UserTask }
  or $@ !~ m:^Can't locate NP/Model/UserTask.pm: and die $@;

{ package NP::Model::VendorZone;

use strict;

use base qw(NP::Model::_Object);

__PACKAGE__->meta->setup(
  table   => 'vendor_zones',

  columns => [
    id                  => { type => 'serial', not_null => 1 },
    id_token            => { type => 'varchar', alias => '_id_token', length => 36 },
    zone_name           => { type => 'varchar', length => 90, not_null => 1 },
    status              => { type => 'enum', check_in => [ 'New', 'Pending', 'Approved', 'Rejected' ], default => 'New', not_null => 1 },
    user_id             => { type => 'integer' },
    organization_name   => { type => 'varchar', length => 255 },
    client_type         => { type => 'enum', check_in => [ 'ntp', 'sntp', 'legacy' ], default => 'sntp', not_null => 1 },
    contact_information => { type => 'text', length => 65535 },
    request_information => { type => 'text', length => 65535 },
    device_information  => { type => 'text', length => 65535 },
    device_count        => { type => 'integer' },
    opensource          => { type => 'integer', default => '0', not_null => 1 },
    opensource_info     => { type => 'text', length => 65535 },
    rt_ticket           => { type => 'integer' },
    approved_on         => { type => 'datetime' },
    created_on          => { type => 'datetime', default => 'now', not_null => 1 },
    modified_on         => { type => 'timestamp', not_null => 1 },
    dns_root_id         => { type => 'integer', not_null => 1 },
    account_id          => { type => 'integer' },
  ],

  primary_key_columns => [ 'id' ],

  unique_keys => [
    [ 'id_token' ],
    [ 'zone_name', 'dns_root_id' ],
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

{ package NP::Model;

  sub db  { shift; NP::Model::_Object->init_db(@_);      }
  sub dbh { shift->db->dbh; }

  my @cache_classes = grep { $_->can('clear_object_cache') } @table_classes;
  sub flush_caches {
    $_->clear_object_cache for @cache_classes;
  }

  sub account_subscription { our $account_subscription ||= bless [], 'NP::Model::AccountSubscription::Manager' }
  sub oidc_public_key { our $oidc_public_key ||= bless [], 'NP::Model::OidcPublicKey::Manager' }
  sub schema_revision { our $schema_revision ||= bless [], 'NP::Model::SchemaRevision::Manager' }
  sub scorer_statu { our $scorer_statu ||= bless [], 'NP::Model::ScorerStatu::Manager' }
  sub server_score { our $server_score ||= bless [], 'NP::Model::ServerScore::Manager' }
  sub server_url { our $server_url ||= bless [], 'NP::Model::ServerUrl::Manager' }
  sub servers_monitor_review { our $servers_monitor_review ||= bless [], 'NP::Model::ServersMonitorReview::Manager' }
  sub system_setting { our $system_setting ||= bless [], 'NP::Model::SystemSetting::Manager' }
  sub user_task { our $user_task ||= bless [], 'NP::Model::UserTask::Manager' }
  sub vendor_zone { our $vendor_zone ||= bless [], 'NP::Model::VendorZone::Manager' }

}
1;
