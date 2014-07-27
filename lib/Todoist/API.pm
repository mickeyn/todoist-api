package Todoist::API;

use Moo;
use Carp;

use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS  qw( decode_json encode_json );

with 'Todoist::API::Account';
with 'Todoist::API::Project';
with 'Todoist::API::Task';
with 'Todoist::API::Premium';

has base_url => (
    is      => 'ro',
    default => sub { 'https://api.todoist.com/API' },
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

sub _build_ua {
    HTTP::Tiny->new( keep_alive => 1 );
}

sub get_timezones {
    my $self = shift;

    my $result = $self->ua->get( $self->base_url . "/getTimezones"  );

    my $tz;
    try   { $tz = decode_json $result->{content} }
    catch { croak 'getting timezones failed' };

    return $tz;
}


1;

__END__

LEFT:

register
deleteUser
updateUser
+ updateAvatar

? query

? uploadFile

??? getRedirectLink
????? LABELS STUFF (payed version)
????? NOTES  STUFF (payed version)

