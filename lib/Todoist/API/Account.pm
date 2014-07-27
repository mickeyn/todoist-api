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

        my $result = $self->ua->post_form(
            $self->base_url . "/updateNotificationSetting",
            {
                token             => $self->token,
                notification_type => $notification_type,
                service           => $service,
                dont_notify       => $dont_notify,
            }
        );

        return $result->{status};
    }
}



1;
