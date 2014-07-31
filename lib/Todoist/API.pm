package Todoist::API;

use Moo;
use Carp;

use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS  qw( decode_json );

BEGIN {
    with qw/ Todoist::API::Role::Account
             Todoist::API::Role::Project
             Todoist::API::Role::Task
             Todoist::API::Role::Premium
           /;
}

my $base_url = 'https://api.todoist.com/API/';

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

    return $self->GET({ cmd => 'getTimezones', no_token => 1 });
}

=item GET

Calls an HTTP GET using the UA.

Taking a hash as an arguemnt, supports the following keys:
{
  cmd         => the API command to execute, # mandatory
  params      => GET URL params as a string.
  status_only => if positive, tells method to return result status
                 instead of the decoded content result.
  no_token    => if positive, tells method to not add token as a
                 URL param (added by default)
}

In case called with a string as argument, will treat it as 'cmd'
without other options.

=cut

sub GET {
    my $self = shift;
    $self->_fetch( 'GET', @_ );
}

=item POST

Calls an HTTP POST using the UA.

Taking a hash as an arguemnt, supports the following keys:
{
  cmd         => the API command to execute, # mandatory
  params      => GET URL params as a string.
  status_only => if positive, tells method to return result status
                 instead of the decoded content result.
  no_token    => if positive, tells method to not add token as a
                 URL param (added by default)
}

In case called with a string as argument, will treat it as 'cmd'
without other options.

=cut

sub POST {
    my $self = shift;
    $self->_fetch( 'POST', @_ );
}

sub _fetch {
    my $self = shift;
    my $type = shift;
    my $args = shift;

    $type eq 'GET' or $type eq 'POST'
        or croak "wrong fetch type GET/POST only";

    ref $args eq 'HASH' or croak "$type called with wrong arguments";

    my $cmd = $args->{cmd};
    $cmd or croak "$type must have a 'cmd' argument";

    my $result;

    if ( $type eq 'GET' ) {
        my $url_params = '';
        $args->{no_token} or $url_params .= 'token=' . $self->token;
        $args->{params}  and $url_params .= '&' . $args->{params};

        $url_params and $url_params =~ s/^/\?/;

        $result = $self->ua->get( $base_url . $cmd . $url_params );

    } else { # POST
        $args->{no_token} or $args->{params}{token} = $self->token;

        $result = $self->ua->post_form(
            $base_url . $cmd,
            $args->{params},
        );
    }

    $args->{status_only} and return [ $result->{status} ];

    my $decoded_result;
    try   { $decoded_result = decode_json $result->{content} }
    catch { croak "$cmd failed" };

    return [ $result->{status}, $decoded_result ];
}


1;

__END__

LEFT:

? query
? uploadFile
??? getRedirectLink
????? LABELS STUFF (payed version)
????? NOTES  STUFF (payed version)

