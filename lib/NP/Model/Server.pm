package NP::Model::Server;
use strict;

sub score_raw {
    my $self = shift;
    local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    warn Data::Dumper->Dump([\$self], [qw(self)]);

    warn "MY ID: ", $self->id; 

    my $sc = $self->score;

    if (@_) {
        $sc->score_raw(@_);
        $sc->save;
    }
    $sc->score_raw;
}

package NP::Model::Server::Manager;
use strict;

sub get_check_due {
    my $class = shift;

    $class->get_objects_from_sql
      (
       sql => q[SELECT s.*
                FROM
                  servers s left join scores sc ON(s.id=sc.server_id)
                WHERE
                  sc.ts IS NULL or sc.ts < DATE_SUB( NOW(), INTERVAL 24 minute)
                  ORDER BY sc.ts
               ],
       
              );
}


1;
