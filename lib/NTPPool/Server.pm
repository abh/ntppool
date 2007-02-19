package NTPPool::Server;
use strict;
use base qw(NTPPool::DBI);
use NTPPool::Server::Score;
use NTPPool::Zone;
use RRDs;
use Time::Piece ();
use Time::Piece::MySQL ();

__PACKAGE__->set_up_table('servers');
__PACKAGE__->has_a('admin' => 'NTPPool::Admin');
__PACKAGE__->has_many('log_scores' => 'NTPPool::Server::LogScore', { cascade => 'None' } );
__PACKAGE__->has_many('locations' => 'NTPPool::Location');
__PACKAGE__->has_many('notes'     => 'NTPPool::Server::Note');
__PACKAGE__->has_many('urls'      => [ 'NTPPool::Server::URL' => 'url' ]);
__PACKAGE__->might_have('_score'  => 'NTPPool::Server::Score');
__PACKAGE__->might_have('_alert'  => 'NTPPool::Server::Alert');


__PACKAGE__->set_sql(bad_score => qq{
                     SELECT s.id
                         FROM servers s, scores sc
                         WHERE s.id=sc.server
                              and sc.score <= 5
                         ORDER BY sc.score desc
               });


__PACKAGE__->set_sql(urls => qq{
                     SELECT DISTINCT s.id
                         FROM servers s, server_urls u
                         WHERE s.id=u.server
                         and (s.in_pool = 1 OR s.in_server_list = 1)
                         ORDER BY s.id
               });



sub note {
    my ($self, $name) = @_;
    my $note = NTPPool::Server::Note->find_or_create({ server => $self, name => $name });
    if ($_[2]) {
        $note->note($_[2]);
        $note->update;
    }
    $note->note;
}

sub country {
  my $self = shift;
  my ($country) = grep { length $_->name == 2 } $self->zones;
  $country && $country->name;
}


1;
