package NP::DB::Scaffold;
use strict;
use base qw(Combust::RoseDB::Scaffold);

# Tables excluded from model generation (migrated to CAPI or not needed)
my @excluded_tables = qw(
    account_invites
    account_users
    accounts
    api_keys
    api_keys_monitors
    dns_roots
    log_scores
    log_scores_archive_status
    logs
    monitor_registrations
    monitors
    oidc_public_keys
    schema_revision
    scorer_statu
    scorer_status
    server_alerts
    server_notes
    server_scores
    server_urls
    server_verifications
    server_verifications_history
    server_zones
    servers
    servers_monitor_review
    system_settings
    user_equipment_applications
    user_identities
    user_privileges
    user_sessions
    users
    vendor_zones
    zone_server_counts
    zones
);

sub db_model_class {
    my ($self, $db) = @_;
    die "unknown database [$db]" unless $db eq 'ntppool';
    "NP::Model";
}

sub convention_manager {
    'NP::DB::ConventionManager';
}

my %json_fields = (
    log_scores             => 'attributes',
    monitors               => 'config',
    servers_monitor_review => 'config',
    system_settings        => 'value',
    logs                   => 'changes',
    servers                => 'flags',
    accounts               => 'flags',
);

sub json_columns {
    my $self = shift;
    my $meta = shift;
    my $cols = $json_fields{$meta->table} or return;

    my @cols = ref($cols) ? @$cols : ($cols);

    return grep { $meta->column($_) } @cols;
}

sub filter_tables {    # Return 0 to exclude a table
    my $self  = shift;
    my $db    = shift;
    my $table = shift;

    return 0 if grep { $_ eq $table } @excluded_tables;
    return $self->SUPER::filter_tables($db, $table);
}

1;
