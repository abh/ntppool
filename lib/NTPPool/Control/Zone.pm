package NTPPool::Control::Zone;
use strict;
use parent qw(NTPPool::Control);
use NP::Model;
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
    my ($zone_name) =
      ($self->request->uri =~ m!^/zone/(?:graph)?([^/]+?)(\.json|/|(-v6)?\.png)?$!);
    $zone_name ||= '.';
    $zone_name;
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
    my ($hist) = grep { $_->{ipVersion} eq $ip_version } @$historical_stats;
    return unless $hist && $hist->{stats};

    # Find the StatPoint with matching daysAgo
    my ($stat) = grep { $_->{daysAgo} == $days } @{$hist->{stats}};
    return unless $stat;

    # Return undef if countActive is missing (API omits zero values)
    return unless defined $stat->{countActive};

    # Return hashref compatible with template expectations
    return {
        count_active => $stat->{countActive},
        ago          => Time::Duration::ago($days * 86400, 2),  # days to seconds
    };
}

sub render {
    my $self      = shift;
    my $zone_name = $self->zone_name;
    return 404 if (length($zone_name) > 100);

    # discourage trailing slashes
    if (my ($path) = ($self->request->path =~ m!^(.*)/$!)) {
        return $self->redirect($1, 301);
    }

    if (my $ip_version = $self->is_graph) {
        $self->cache_control('max-age=10800, s-maxage=7200');
        return 404;
    }
    elsif ($self->request->path =~ m!\.json$!) {
        my $limit = $self->req_param('limit') || 0;

        $self->request->header_out('Fastly-Follow' => '1');
        return $self->redirect(
            $self->www_url(
                "/api/data/zone/counts/" . $zone_name,
                {($limit ? (limit => $limit) : ())}
            ),
            301
        );
    }

    # Fetch zone from CAPI
    my $zone_result = get_zone(
        name    => $zone_name,
        context => $self->_get_request_context(),
    );

    if ($zone_result->{error}) {
        warn "Zone API error: $zone_result->{error} (trace: $zone_result->{trace_id})";
        return 404 if $zone_result->{code} == 404;
        return 500;
    }

    my $zone = $zone_result->{data}{zone};
    return 404 unless $zone;

    $self->tpl_param('zone' => $zone);

    $self->cache_control('s-maxage=900, max-age=1800');

    return OK, $self->evaluate_template('tpl/zone.html');
}

1;
