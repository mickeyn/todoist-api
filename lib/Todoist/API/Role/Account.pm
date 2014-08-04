package Todoist::API::Role::Account;

use Moo::Role;
use Carp;

use Todoist::Utils qw( read_password );

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
        token       => $self->api_token,
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
        token  => $self->api_token,
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
        token  => $self->api_token,
        cmd    => 'updateAvatar',
        params => $params,
    });
}

sub ping {
    my $self = shift;

    my $status = $self->GET({
        token       => $self->api_token,
        cmd         => 'ping',
        status_only => 1,
    });

    return 0+!!($status == 200 );
}

sub productivity_stats {
    my $self = shift;

    return $self->GET({
        token => $self->api_token,
        cmd   => 'getProductivityStats'
    });
}

sub notification_settings {
    my $self = shift;

    return $self->GET({
        token => $self->api_token,
        cmd   => 'getNotificationSettings'
    });
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
            token       => $self->api_token,
            cmd         => 'updateNotificationSetting',
            params      => $params,
            status_only => 1,
        });
    }
}


1;
