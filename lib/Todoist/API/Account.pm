package Todoist::API::Account;

use Moo::Role;
use Carp;

use Todoist::Utils qw( read_password );

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

    my $login = $self->POST({
        cmd      => 'login',
        params   => { email => $self->email, password => $passwd },
        no_token => 1,
    });

    undef $passwd;
    return $login;
}

sub login_google {
    my $self = shift;
    my $args = shift;

    my $oauth2_token = $args->{oauth2_token} || return;

    my $params = {
        email        => $self->email,
        oauth2_token => $oauth2_token,
      ( auto_signup  => $args->{auto_signup} )x!! exists $args->{auto_signup},
      ( full_name    => $args->{full_name}   )x!! exists $args->{full_name},
      ( timezone     => $args->{timezone}    )x!! exists $args->{timezone},
      ( lang         => $args->{lang}        )x!! exists $args->{lang},
    };

    my $login = $self->POST({
        cmd      => 'loginWithGoogle',
        params   => $params,
        no_token => 1,
    });

    $self->td_user( $login );
    return 1;
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
        email     => $self->email,
        password  => $passwd,
        full_name => $name,
      ( lang      => $args->{lang}     )x!! $args->{lang},
      ( timezone  => $args->{timezone} )x!! $args->{timezone},
    };

    return $self->POST({
        cmd      => 'register',
        params   => $params,
        no_token => 1,
    });
}

sub ping {
    my $self = shift;

    my $status = $self->GET({
        cmd         => 'ping',
        status_only => 1,
    });

    return 0+!!($status == 200 );
}

sub productivity_stats {
    my $self = shift;

    return $self->GET({ cmd => 'getProductivityStats' });
}

sub notification_settings {
    my $self = shift;

    return $self->GET({ cmd => 'getNotificationSettings' });
}

{
    my @valid_notification_types = qw/
        share_invitation_sent
        share_invitation_accepted
        share_invitation_rejected
        user_left_project
        user_removed_from_project
        item_assigned
        item_completed
        item_uncompleted
        note_added
        biz_policy_disallowed_invitation
        biz_policy_rejected_invitation
        biz_trial_will_end
        biz_payment_failed
        biz_account_disabled
        biz_invitation_created
        biz_invitation_accepted
        biz_invitation_rejected
    /;

    sub update_notification_setting {
        my $self = shift;
        my $args = shift;
        ref $args eq 'HASH' or return;

        my $notification_type = $args->{notification_type};
        grep { $notification_type eq $_ } @valid_notification_types or return;

        my $service = $args->{service};
        $service eq 'email' or $service eq 'push' or return;

        my $dont_notify = $args->{dont_notify};
        $dont_notify == 0 or $dont_notify == 1 or return;

        my $params = {
            notification_type => $notification_type,
            service           => $service,
            dont_notify       => $dont_notify,
        };

        return $self->POST({
            cmd         => 'updateNotificationSetting',
            params      => $params,
            status_only => 1,
        });
    }
}


1;
