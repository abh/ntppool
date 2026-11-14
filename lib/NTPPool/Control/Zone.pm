package NTPPool::Control::Zone;
use strict;
use parent            qw(NTPPool::Control);
use Combust::Constant qw(OK);
use JSON              qw(encode_json);
use List::Util        qw(uniq);
use experimental      qw( defer );
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_INTERNAL SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;
use NP::CAPI::Zone qw(get_zone);
use Time::Duration qw();

sub zone_name {
    my $self = shift;
    my $uri  = $self->request->uri;
    return '.' if $uri eq '/zone';
    my ($zone_name) = ($uri =~ m!^/zone/(?:graph)?([^/]+?)(\.json|/|(-v6)?\.png)?$!);
    return $zone_name;
}

sub is_graph {
    my $self = shift;
    return unless $self->request->path =~ m!^/zone/graph!;
    return $self->request->path =~ m/-v6.png$/ ? 'v6' : 'v4';
}

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

sub random_subzone_ids {
    my ($self, $count) = @_;
    my $SUB_ZONE_COUNT = 4;
    $count = $SUB_ZONE_COUNT if $count > $SUB_ZONE_COUNT;
    my %ids;

    do {
        my $id = int(rand($SUB_ZONE_COUNT));
        $ids{$id} = undef;
    } until (keys %ids == $count);

    return keys %ids;
}

sub get_zone_stats {
    my ($self, $historical_stats, $days, $ip_version) = @_;
    return unless $historical_stats && ref($historical_stats) eq 'ARRAY';

    # Find the HistoricalStats for the requested IP version
    my ($hist) = grep { $_->{ip_version} eq $ip_version } @$historical_stats;
    return unless $hist && $hist->{stats};

    # Find the StatPoint with matching days_ago
    my ($stat) = grep { $_->{days_ago} == $days } @{$hist->{stats}};
    return unless $stat;

    # Return undef if count_active is missing (API omits zero values)
    return unless defined $stat->{count_active};

    # Return hashref compatible with template expectations
    return {
        count_active => $stat->{count_active},
        ago          => Time::Duration::ago($days * 86400, 2),    # days to seconds
    };
}

sub render {
    my $self = shift;

    # discourage trailing slashes
    if (my ($path) = ($self->request->path =~ m!^(.*)/$!)) {
        return $self->redirect($path, 301);
    }

    my $zone_name = $self->zone_name;
    return 404 unless defined $zone_name && length($zone_name) <= 100;

    if (my $ip_version = $self->is_graph) {
        $self->cache_control('max-age=10800, s-maxage=7200');
        return 404;
    }

    my $is_json = $self->request->path =~ m!\.json$!;

    # Fetch zone from CAPI. The API matches the name ignoring case and
    # returns it as stored.
    my $zone_result = get_zone(
        name    => $zone_name,
        context => $self->_get_request_context(),
        ($is_json ? (basic_only => JSON::true) : ()),
    );

    if (my $status = $self->capi_error_status($zone_result, $zone_result->{data}{zone})) {
        warn "Zone API error: $zone_result->{error} (trace: $zone_result->{trace_id})"
          if $zone_result->{error};
        return $status;
    }

    my $zone = $zone_result->{data}{zone};

    if ($is_json) {
        my $limit = $self->req_param('limit') || 0;

        $self->request->header_out('Fastly-Follow' => '1');
        return $self->redirect(
            $self->www_url(
                "/api/data/zone/counts/" . $zone->{name},
                {($limit ? (limit => $limit) : ())}
            ),
            301
        );
    }

    if ($zone->{name} ne $zone_name) {
        return $self->redirect($zone->{url}, 301);
    }

    $self->tpl_param('zone' => $zone);

    $self->cache_control('s-maxage=900, max-age=1800');

    return OK, $self->evaluate_template('tpl/zone.html');
}

1;
