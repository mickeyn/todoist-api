package Todoist::API;

use Moo;
use Carp;

use Try::Tiny;
use HTTP::Tiny;
use JSON::MaybeXS  qw( decode_json );
use Todoist::Utils qw( read_password );
use Todoist::API::User;

my $base_url = 'https://api.todoist.com/API/';

has [ qw<email password> ] => (
    is => 'ro',
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

sub _build_ua {
    HTTP::Tiny->new( keep_alive => 1 );
}

# alias to 'email'
sub username { shift->email }

sub _login {
    my ( $self, $email, $password ) = @_;

    $email && $password
        or die "Missing username/email and/or password\n";

    my $args = $self->POST( {
        cmd    => 'login',
        params => { email => $email, password => $password },
    } );

    # TODO: make register_user also return a user? (or stick to the API output)
    return Todoist::API::User->new({
        api => $self,
        %{ $args },
    });

}

sub BUILDARGS {
    my ( $class, @args ) = @_;

    my %args = @args % 2 ? %{ $args[0] } : @args;

    $args{'username'}
        and $args{'email'} = delete $args{'username'};

    return \%args;
}

sub login {
    my $self = shift;
    return $self->_login( $self->email, $self->password );
}

# TODO: BUILDARGS? check args

sub get_timezones {
    my $self = shift;

    return $self->GET({ cmd => 'getTimezones' });
}

sub login_google {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or croak 'args to login_google must be a hash';

    my $email = $args->{email} || $args->{user};
    $email or croak 'login must receive an email/user as a param';

    my $oauth2_token = $args->{oauth2_token} || return;

    my $params = {
        email        => $email,
        oauth2_token => $oauth2_token,
      ( auto_signup  => $args->{auto_signup} )x!! exists $args->{auto_signup},
      ( full_name    => $args->{full_name}   )x!! exists $args->{full_name},
      ( timezone     => $args->{timezone}    )x!! exists $args->{timezone},
      ( lang         => $args->{lang}        )x!! exists $args->{lang},
    };

    my $login = $self->POST({
        cmd    => 'loginWithGoogle',
        params => $params,
    });

    return Todoist::API::User->new({
        api => $self,
        %{$login},
    });
}

sub register_user {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or croak "register_user args can only be a hash";

    my $email = $args->{email};
    $email or croak "register_user requires an email";

    my $name = $args->{name};
    $name or croak "register_user requires a full name";

    my $passwd = read_password();

    my $params = {
        email     => $email,
        password  => $passwd,
        full_name => $name,
      ( lang      => $args->{lang}     )x!! $args->{lang},
      ( timezone  => $args->{timezone} )x!! $args->{timezone},
    };

    return $self->POST({
        cmd    => 'register',
        params => $params,
    });
}

=item GET

Calls an HTTP GET using the UA.

Taking a hash as an arguemnt, supports the following keys:
{
  cmd         => the API command to execute, # mandatory
  params      => GET URL params as a string.
  status_only => if positive, tells method to return result status
                 instead of the decoded content result.
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

    my $params = $args->{params} || {};
    ref $params eq 'HASH' or croak 'params must be a hash';

    $args->{token} and $params->{token} = $args->{token};

    my $result;

    if ( $type eq 'GET' ) {
        my $url_params = '';
        for ( keys %{ $params } ) {
            $url_params .= '&' . "$_=" . $params->{$_};
        }

        $url_params and $url_params =~ s/^\&?/\?/;

        $result = $self->ua->get( $base_url . $cmd . $url_params );

    } else { # POST
        $result = $self->ua->post_form(
            $base_url . $cmd,
            $params,
        );
    }

    $args->{status_only} and return $result->{status};

    $result->{status} == 200 or
        ( carp "$cmd failed with exit-stats = " . $result->{status} and return );

    my $decoded_result;
    try   { $decoded_result = decode_json $result->{content} }
    catch { croak "$cmd failed" };

    return $decoded_result;
}


1;

__END__

LEFT:

? query
? uploadFile
??? getRedirectLink
????? LABELS STUFF (payed version)
????? NOTES  STUFF (payed version)

