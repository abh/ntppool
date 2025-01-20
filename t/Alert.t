use Test::More tests => 9;
use strict;

BEGIN {
  use_ok('NP::Model');
}

my $dbh = NP::Model->dbh;
my $db = NP::Model->db;
$db->begin_scoped_work;

END {
  $dbh->do(q[delete from servers where ip like '127.0.0.%']);
  $dbh->do(q[delete from users where email like '%@example.com']);
};


ok(my $admin  = NP::Model->user->create(email => 'test@example.com'), 'create admin');
$admin->save;
ok(my $server = NP::Model->server->create(user => $admin, ip => '127.0.0.2'), "create server");
$server->save;
ok(my $alert  = $server->alert, 'create alert');
ok($alert->mark_sent, 'mark_sent');
ok(sleep 2, 'wait a few seconds');

ok($alert  = $server->alert, 'create alert');
ok($alert->mark_sent, 'mark_sent');
isnt($alert->first_email_time, $alert->last_email_time, 'different last_email_time than first_email_time');

$db->rollback;
