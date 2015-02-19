package NP::Util;
use strict;
use warnings;
use HTML::Entities qw(encode_entities);
use Exporter;
use Encode ();
use Carp qw(croak);
use Data::Transformer ();

our @EXPORT_OK = qw(
  convert_to_html
  run
  utf8_safe
  utf8_safe_tree
  uniq
);

sub convert_to_html {
    my $str = shift;

    encode_entities($str, '<>&"');    # how can we encode everything without messing up UTF8?
    $str =~ s!(https?://.+?)(\s|$)!<a href="$1">$1</a>$2!g;
    $str =~ s!\n\s*[\n\s]+!<br/><br/>!g;
    $str =~ s!\n!<br/>\n!g;

    $str;
}

sub run {
    my @ar = @_;
    my $parms = ref $ar[-1] eq "HASH" ? pop @ar : {};

    print "Running: ", join(" ", @ar), "\n" unless $parms->{silent};

    return 1 if system(@ar) == 0;

    my $exit_value = $? >> 8;
    return 0
      if $parms->{fail_silent_if}
      && $exit_value == $parms->{fail_silent_if};

    my $msg = "system @ar failed: $exit_value ($?)";
    croak($msg) unless $parms->{failok};
    print "$msg\n";
    return 0;
}

sub utf8_safe {
    my $text = shift;
    $text = Encode::decode("windows-1252", $text)
      unless utf8::is_utf8($text)
      or utf8::decode($text);
    return $text;
}

sub utf8_safe_tree {
    my $data = shift;
    Data::Transformer->new(
        normal => sub {
            ${$_[0]} = utf8_safe(${$_[0]}) if ${$_[0]};
        }
    )->traverse($data);
    $data;
}

sub uniq (@) {
    my %seen = ();
    grep { not $seen{$_}++ } @_;
}

1;

