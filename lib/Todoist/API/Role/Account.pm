package Todoist::API::Role::Account;

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

    $login->[0] == 200 or croak 'login failed';

    return $login->[1];
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

    $login->[0] == 200 or croak 'login failed';

    $self->td_user( $login->[1] );
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

sub delete_user {
    my $self = shift;
    my $args = shift;

    my ( $reason, $in_background );
    if ( $args and ref $args eq 'HASH' ) {
        $reason        = $args->{reason};
        $in_background = $args->{in_background};
    }

    my $passwd = read_password();

    my $params = {
        current_password  => $passwd,
      ( reason_for_delete => $reason        )x!! $reason,
      ( in_background     => $in_background )x!! $in_background,
    };

    return $self->POST({
        cmd         => 'deleteUser',
        params      => $params,
        status_only => 1,
    });
}

sub update_user {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or croak 'args to update_user must be a hash';

    my $passwd;
    $args->{password} and $passwd = read_password();

    my $params = {
      ( email            => $args->{email}            )x!! $args->{email},
      ( full_name        => $args->{name}             )x!! $args->{name},
      ( password         => $args->{passwd}           )x!! $args->{passwd},
      ( timezone         => $args->{timezone}         )x!! $args->{timezone},
      ( date_format      => $args->{date_format}      )x!! $args->{date_format},
      ( time_format      => $args->{time_format}      )x!! $args->{time_format},
      ( start_day        => $args->{start_day}        )x!! $args->{start_day},
      ( next_week        => $args->{next_week}        )x!! $args->{next_week},
      ( start_page       => $args->{start_page}       )x!! $args->{start_page},
      ( default_reminder => $args->{default_reminder} )x!! $args->{default_reminder},
    };

    return $self->POST({
        cmd    => 'updateUser',
        params => $params,
    });
}

sub update_avatar {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or croak 'args to update_avatar must be a hash';

    my $image  = $args->{image};
    my $delete = $args->{delete};

    $image or $delete or return;

    # TODO: check: image must be encoded data with multipart/form-data, max 2MB

    my $params = {
        ( image  => $image  )x!! $image,
        ( delete => $delete )x!! $delete,
    };

    return $self->POST({
        cmd    => 'updateAvatar',
        params => $params,
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