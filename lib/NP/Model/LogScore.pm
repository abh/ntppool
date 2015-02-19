package NP::Model::LogScore;
use strict;

sub save {
    my $self = shift;
    my $rv   = $self->SUPER::save(@_);
    $rv;
}

sub history_symbol {
    my $self = shift;
    _symbol($self->step);
}

sub history_css_class {
    my $self = shift;
    _css_class($self->step);
}

sub _css_class {
    my $step = shift;
    if    ($step >= 0)  { return 's_his s_his_ok'; }
    elsif ($step >= -1) { return 's_his s_his_tol'; }
    elsif ($step >= -4) { return 's_his s_his_big'; }
    else                { return 's_his s_his_down'; }
}

sub _symbol {
    my $step = shift;
    if    ($step >= 0)  { return '#'; }
    elsif ($step >= -1) { return 'x'; }
    elsif ($step >= -4) { return 'o'; }
    else                { return '_'; }
}

1;
