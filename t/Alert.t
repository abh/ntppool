use Test::More tests => 10;
use strict;

BEGIN {
  use_ok('NP::Model');
}

my $dbh = NP::Model->dbh;

END {
  $dbh->do(q[delete from servers where ip like '127.0.0.%']);
  $dbh->do(q[delete from users where email like '%@example.com']);
};


ok(my $admin  = NP::Model::User->new( email => 'test@example.com'), 'create admin');
ok(my $server = NP::Model::Server->new(user => $admin, ip => '127.0.0.2'), "create server");
ok(my $alert  = $server->alert, 'create alert');
ok($alert->mark_sent, 'mark_sent');
ok(sleep 2, 'wait a few seconds');

ok($alert  = $server->alert, 'create alert');
ok($alert->mark_sent, 'mark_sent');
ok($alert->first_email_time ne $alert->last_email_time, 'different last_email_time than first_email_time');



