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
{ package NP::Model;

  sub db  { shift; NP::Model::_Object->init_db(@_);      }
  sub dbh { shift->db->dbh; }

  my @cache_classes = grep { $_->can('clear_object_cache') } @table_classes;
  sub flush_caches {
    $_->clear_object_cache for @cache_classes;
  }

  sub account_subscription { our $account_subscription ||= bless [], 'NP::Model::AccountSubscription::Manager' }

}
1;
