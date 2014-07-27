package Todoist::API::Account;

use Moo::Role;

use Todoist::Utils qw( read_password );

use Carp;
use Try::Tiny;
use JSON::MaybeXS qw( decode_json encode_json );

has email => (
    is       => 'ro',
    isa      => sub { !ref $_[0] or croak "wrong type for email" },
    required => 1
);

has td_user => (
    is      => 'rw',
    isa     => sub { ref $_[0] eq 'HASH' or croak "wrong type for td_user" },
    lazy    => 1,
    builder => '_build_td_user',
);

sub _build_td_user {
    my $self = shift;

    $self->login();
}


sub token {
    my $self = shift;

    return $self->td_user->{api_token};
}

sub login {
    my $self = shift;

    my $passwd = read_password();

    my $result = $self->ua->post_form(
        $self->base_url . "/login",
        { email => $self->email, password => $passwd }
    );
    undef $passwd;

    my $login;
    try   { $login = decode_json $result->{content} }
    catch { croak 'login failed' };

    return $login;
}

# TODO: wasn't testet yet
sub login_google {
    my $self = shift;
    my $args = shift;

    exists $args->{oauth2_token} or return;

    my $result = $self->ua->post_form(
        $self->base_url . "/loginWithGoogle",
        {
            email        => $self->email,
            oauth2_token => $args->{oauth2_token},
          ( auto_signup  => $args->{auto_signup} )x!! exists $args->{auto_signup},
          ( full_name    => $args->{full_name}   )x!! exists $args->{full_name},
          ( timezone     => $args->{timezone}    )x!! exists $args->{timezone},
          ( lang         => $args->{lang}        )x!! exists $args->{lang},
        }
    );

    my $login;
    try   { $login = decode_json $result->{content} }
    catch { croak 'login failed' };

    $self->td_user( $login );

    return $result->{status};
}

sub ping {
    my $self = shift;

    my $result = $self->ua->get(
        $self->base_url . "/ping?token=" . $self->token
    );

    return 0+!!($result->{status} == 200 );
}

sub productivity_stats {
    my $self = shift;

    my $result = $self->ua->get(
        $self->base_url . "/getProductivityStats?token=" . $self->token,
    );

    my $stats;
    try   { $stats = decode_json $result->{content} }
    catch { croak 'getting stats failed' };

    return $stats;
}

sub notification_settings {
    my $self = shift;

    my $result = $self->ua->get(
        $self->base_url . "/getNotificationSettings?token=" . $self->token,
    );

    my $settings;
    try   { $settings = decode_json $result->{content} }
    catch { croak 'getting settings failed' };

    return $settings;
}


1;
