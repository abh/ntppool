package NTPPool::API::Notes;
use strict;
use base qw(NTPPool::API::Base);
use NP::Model;
use Net::IP;

sub set {
    my $self = shift;

    my $api_key = $self->api_key or die "api_key required\n";

    my $ip = Net::IP->new($self->_required_param('ip'));

    my $name = $self->_required_param('name');
    my $text = $self->_optional_param('note');

    my $server = NP::Model->server->find_server($ip->ip)
      or die "Could not find server";

    my $note = NP::Model->server_note->fetch_or_create( server_id => $server->id, name => $name );

    $note->note($text);
    $note->modified_on('now');
    $note->save;

    return { ok => 1 };
}

1;
