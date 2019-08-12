package NP::Model::Log;
use strict;
use Scalar::Util ();
use String::Diff ();
use JSON::XS qw(encode_json);
use Data::Dump qw(pp);

sub log_changes {
    my $class = shift;

    my $user    = shift;
    my $type    = shift;
    my $message = shift;

    my $new = shift;
    my $old = shift;
    if ($old and Scalar::Util::blessed($old) && $old->can('get_data_hash')) {
        $old = $old->get_data_hash();
    }

    my %log = (message => $message, type => $type);

    if ($user) {
        $log{user_id} = $user->id;
    }

    if ($new->isa('NP::Model::Server')) {
        $log{server_id} = $new->id;
    }

    if ($new->isa('NP::Model::Account')) {
        $log{account_id} = $new->id;
    }

    if (!$log{account_id} and $new->can('account')) {
        $log{account_id} = $new->account_id;

        # todo: log account id changing?
    }

    my %changes;
    if ($old and $new) {
        my %update;
        for my $f ($new->meta->columns) {
            next if $f->name =~ m/^(modified|created)_on$/;

            # warn "F: $f", pp($f);
            local $^W;    # no uninit warnings
            my $nf = $new->$f;
            my $of = $old->{$f};
            if (eval { $nf->isa('DateTime') }) {
                $nf = $nf->datetime;
            }
            if (eval { $of->isa('DateTime') }) {
                $of = $of->datetime;
            }
            unless ($nf eq $of) {
                my $diff = String::Diff::diff_merge(
                    $of, $nf,
                    remove_open  => '<del>',
                    remove_close => '</del>',
                    append_open  => '<ins>',
                    append_close => '</ins>',
                );
                $update{$f} = [$nf, $of, $diff];
            }
        }
        $log{changes} = encode_json(\%update);
    }

    my $log = NP::Model->log->create(%log);
    $log->save();
}

1;

__END__

  columns => [
    server_id      => { type => 'integer' },
    user_id        => { type => 'integer' },
    vendor_zone_id => { type => 'integer' },
    type           => { type => 'varchar', length => 50 },
    title          => { type => 'varchar', length => 255 },
    message        => { type => 'text', length => 65535 },
    created_on     => { type => 'datetime', default => 'now', not_null => 1 },
  ],


        if (%old) {
            my @update = "updated job information:";
            for my $f ($job->logged_fields) {
                local $^W; # no uninit warnings
                my $nf = $job->$f;
                my $of = $of{$f};
                if (eval { $nf->isa('DateTime') }) {
                   $nf = $nf->datetime;
                }
                if (eval { $of->isa('DateTime') }) {
                   $of = $of->datetime;
                }
                unless ($nf eq $of) {
                    my $diff = String::Diff::diff_merge(
                        $of, $nf,
                        remove_open  => '<del>',
                        remove_close => '</del>',
                        append_open  => '<ins>',
                        append_close => '</ins>',
                    );
                    push @update, "*$f*: $diff";
                }
            }
            my $update = join "\n", @update;
            $job->log_event( $c->user->id, $update );

        }
