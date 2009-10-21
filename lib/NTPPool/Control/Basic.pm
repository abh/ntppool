package NTPPool::Control::Basic;
use base qw(NTPPool::Control Combust::Control::Basic);

sub render {
    my $self = shift;
    if ($self->request->uri =~ m!^/robots.txt$!) {
        $self->force_template_processing(1)
    }
    else {
        $self->localize_url;
    }

    return $self->SUPER::render(@_);
}

sub servers_with_urls {
    my $self = shift;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $servers = NP::Model->server->get_servers
        (query => [ or =>
                    [ 'in_pool' => 1,
                      'in_server_list' => 1,
                     ],
                    'deletion_on' => undef,
                    'score_raw' => { gt => 0 },
                   ],
         require_objects => ['server_urls'],
         sort_by         => 'id',
         );
    $servers;
}

package NTPPool::Control::Error;
use base qw(NTPPool::Control Combust::Control::Error);

1;
