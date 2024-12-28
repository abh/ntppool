package NTPPool::Control::Zone;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK);
use JSON              qw(encode_json);
use List::Util        qw(uniq);
use experimental      qw( defer );
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_INTERNAL SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;

sub zone_name {
    my $self = shift;
    my ($zone_name) = ($self->request->uri =~ m!^/zone/(?:graph)?([^/]+?)(\.json|/|(-v6)?\.png)?$!);
    $zone_name ||= '.';
    $zone_name;
}

sub is_graph {
    my $self = shift;
    return unless $self->request->path =~ m!^/zone/graph!;
    return $self->request->path =~ m/-v6.png$/ ? 'v6' : 'v4';
}

# TODO: make the web interface actually do this
sub sort_order {
    my $self = shift;
    my $sort = $self->req_param('sort') || '';
    $sort = 'description' unless $sort eq 'server_count';
}

sub show_servers_access {
    my $self = shift;
    return $self->{_show_servers_access} if defined $self->{_show_servers_access};
    return $self->{_show_servers_access} = 1
      if $self->user
      and $self->user->privileges
      and $self->user->privileges->see_all_servers;

    return $self->{_show_servers_access} = 0;
}

sub show_servers {
    my $self = shift;
    return 1 if $self->req_param('show_servers') and $self->show_servers_access;
    return 0;
}

sub render {
    my $self      = shift;
    my $zone_name = $self->zone_name;
    return 404 if (length($zone_name) > 100);
    my $zone = NP::Model->zone->fetch(name => $zone_name);
    return 404 unless $zone;

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

        # $self->request->header_out('Cache-Control' => 'public,max-age=86400,s-maxage=86400');
        $self->request->header_out('Fastly-Follow' => '1');
        return $self->redirect(
            $self->www_url(
                "/api/data/zone/counts/" . $zone->name,
                {($limit ? (limit => $limit) : ())}
            ),
            301
        );
    }

    $self->tpl_param('zone' => $zone);

    $self->tpl_param('is_logged_in' => $self->show_servers_access);
    $self->tpl_param('show_servers' => $self->show_servers);
    if ($self->show_servers) {
        my @servers = sort { $a->ip cmp $b->ip } $zone->servers;
        $self->tpl_param('servers', \@servers);
    }

    unless ($self->show_servers_access) {
        $self->cache_control('s-maxage=900, max-age=1800');
    }
    else {
        $self->cache_control('private');
    }

    return OK, $self->evaluate_template('tpl/zone.html');
}

1;
