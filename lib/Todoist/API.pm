package Todoist::API;

use Moo;
use Carp;

use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS  qw( decode_json encode_json );
use List::Util     qw( first );
use Todoist::Utils qw( read_password );

my $base_url = 'https://api.todoist.com/API';
my $re_id    = qr/^[0-9]+$/;

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

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

has projects => (
    is      => 'rw',
    isa     => sub { ref $_[0] eq 'ARRAY' or croak "wrong type for projects" },
    lazy    => 1,
    builder => '_build_projects',
    clearer => '_clear_projects',
);

has _name2project => (
    is      => 'rw',
    isa     => sub { ref $_[0] eq 'HASH' or croak "wrong type for projects" },
    lazy    => 1,
    builder => '_build_name2project',
    clearer => '_clear_name2project',
);

has _pname2tasks => (
    is      => 'rw',
    isa     => sub { ref $_[0] eq 'HASH' or croak "wrong type for projects" },
    default => sub { +{} },
);

sub _build_ua {
    HTTP::Tiny->new( keep_alive => 1 );
}

sub _build_td_user {
    my $self = shift;

    $self->login();
}

sub _build_projects {
    my $self = shift;

    my $result = $self->ua->get(
        "$base_url/getProjects?token=" . $self->token
    );

    my $projects;
    try   { $projects = decode_json( $result->{content} ) }
    catch { return +{} };

    ref $projects eq 'ARRAY' or return {};

    return $projects;
}

sub _build_name2project {
    my $self = shift;

    +{
        map { $_->{name} => $_ }
        @{ $self->projects }
     };
}

sub get_timezones {
    my $self = shift;

    my $result = $self->ua->get( "$base_url/getTimezones"  );

    my $tz;
    try   { $tz = decode_json $result->{content} }
    catch { croak 'getting timezones failed' };

    return $tz;
}

sub token {
    my $self = shift;

    return $self->td_user->{api_token};
}

sub ping {
    my $self = shift;

    my $result = $self->ua->get(
        "$base_url/ping?token=" . $self->token
    );

    return 0+!!($result->{status} == 200 );
}

sub login {
    my $self = shift;

    my $passwd = read_password();

    my $result = $self->ua->post_form(
        "$base_url/login",
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
        "$base_url/loginWithGoogle",
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

sub productivity_stats {
    my $self = shift;

    my $result = $self->ua->get(
        "$base_url/getProductivityStats?token=" . $self->token,
    );

    my $stats;
    try   { $stats = decode_json $result->{content} }
    catch { croak 'getting stats failed' };

    return $stats;
}

sub project {
    my $self = shift;
    my $name = shift || return;

    my $id = $self->project_name2id($name);

    my $result = $self->ua->get(
        sprintf("$base_url/getProject?token=%s&project_id=%d", $self->token, $id)
    );

    my $project;
    try   { $project = decode_json( $result->{content} ) }
    catch { return +{} };

    return $project;
}

sub add_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    exists $args->{name} or return;

    my $params = {
        token => $self->token,
        name  => $args->{name},
        $self->_optional_project_params($args),
    };

    my $result = $self->ua->post_form(
        "$base_url/addProject",
        $params
    );

    my $add;
    try   { $add = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $add->{id};
}

sub update_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    if ( ! $args->{id} and $args->{name} ) {
        $args->{id} = $self->project_name2id( $args->{name} );
    }

    my $params = {
        token      => $self->token,
        project_id => $args->{id},
      ( name       => $args->{name} )x!! $args->{name},
        $self->_optional_project_params($args),
    };

    my $result = $self->ua->post_form(
        "$base_url/updateProject",
        $params
    );

    my $update;
    try   { $update = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $update->{id};
}

sub update_project_orders {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $ids = $args->{ids};
    ( $ids and ref $ids eq 'ARRAY' and @$ids > 0 ) or return;

    for ( @$ids ) {
        /$re_id/ or $_ = $self->project_name2id($_) or return;
    }

    my $result = $self->ua->post_form(
        "$base_url/updateProjectOrders",
        {
            token        => $self->token,
            item_id_list => encode_json $ids,
        }
    );

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $result->{status};
}

sub delete_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    if ( ! $args->{id} and $args->{name} ) {
        $args->{id} = $self->project_name2id( $args->{name} );
    }

    my $result = $self->ua->get(
        sprintf("$base_url/deleteProject?token=%s&project_id=%d",
                $self->token, $args->{id})
    );

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $result->{status};
}

# Premium
sub archive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    if ( ! $args->{id} and $args->{name} ) {
        $args->{id} = $self->project_name2id( $args->{name} );
    }

    my $result = $self->ua->get(
        sprintf("$base_url/archiveProject?token=%s&project_id=%d",
                $self->token, $args->{id})
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'archiving project failed' };

    return $archived;
}

# Premium
sub unarchive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $id = $args->{id};

    if ( ! $id and $args->{name} ) {
        $id = $self->project_name2id( $args->{name} );
    }

    ( $id and $id =~ /$re_id/ ) or return;

    my $result = $self->ua->get(
        sprintf("$base_url/unarchiveProject?token=%s&project_id=%d",
                $self->token, $id)
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'archiving project failed' };

    return $archived;
}

# Premium
sub get_archived_projects {
    my $self = shift;

    my $result = $self->ua->get(
        "$base_url/getArchived?token=" . $self->token
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'getting archived projects failed' };

    return $archived;
}

sub _refresh_projects_attr {
    my $self = shift;

    $self->_clear_name2project;
    $self->_clear_projects;
}

sub _refresh_project_tasks {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $id   = $args->{id};
    my $name = $args->{name};

    if ( ! $id and $name ) {
        $id = $self->project_name2id( $name );
    }

    if ( ! $name ) {
        my $p = first { $_->{id} == $id } @{ $self->projects };
        $name = $p->{name};
    }

    my $result = $self->ua->get(
        sprintf("$base_url/getUncompletedItems?token=%s&project_id=%d", $self->token, $id)
    );

    my $tasks;
    try   { $tasks = decode_json( $result->{content} ) }
    catch { return +{} };

    $self->_pname2tasks->{$name} = $tasks;
}

sub project_tasks {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $id   = $args->{id};
    my $name = $args->{name};

    if ( ! $id and $name ) {
        $id = $self->project_name2id( $name );
    }

    $self->_refresh_project_tasks({ id => $id });


    return $self->_pname2tasks->{ $name };
}

sub tasks_by_id {
    my $self = shift;
    my $args = shift;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY'       or return;
    grep { !/$re_id/ } @$ids and return;

    my $result = $self->ua->post_form(
        "$base_url/getItemsById",
        {
            token => $self->token,
            ids   => encode_json $ids,
        }
    );

    my $tasks;
    try   { $tasks = decode_json( $result->{content} ) }
    catch { return };

    return $tasks;
}

sub add_task {
    my $self = shift;
    my $args = shift;

    exists $args->{content} or return;

    my $pid = $args->{project_id};
    if ( ! $pid ) {
        $args->{project_name} ||= 'Inbox';
        $pid = $self->project_name2id( $args->{project_name} );
    }

    my $params = {
        token      => $self->token,
        content    => $args->{content},
        project_id => $pid,
        $self->_optional_task_params($args),
    };

    my $result = $self->ua->post_form(
        "$base_url/addItem",
        $params
    );

    my $add;
    try   { $add = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and
        $self->_refresh_project_tasks({ project_id => $pid });

    return $add->{id};
}

sub delete_task {
    my $self = shift;
    my $id   = shift;

    ( !ref $id and $id =~ /$re_id/ ) or return;

    return $self->delete_tasks([ $id ]);
}

sub delete_tasks {
    my $self = shift;
    my $ids  = shift;

    ( ref $ids eq 'ARRAY' and @$ids > 0 ) or return;

    # find matching pids for later update
    my @pnames;
    for ( @$ids ) {
        my $pname = first { $_ } keys %{ $self->_pname2tasks };
        push @pnames => $pname;
    }

    my $result = $self->ua->post_form(
        "$base_url/deleteItems",
        {
            token => $self->token,
            ids   => encode_json $ids,
        }
    );

    for ( @pnames ) {
        $self->_refresh_project_tasks({ project_name => $_ });
    }

    return $result->{status};
}

sub update_task {
    my $self = shift;
    my $args = shift;

    exists $args->{id} or return;

    my $params = {
        token => $self->token,
        id    => $args->{id},
      ( content => $args->{content} )x!! $args->{content},
        $self->_optional_task_params($args),
    };

    my $result = $self->ua->post_form(
        "$base_url/updateItem",
        $params
    );

    my $update;
    try   { $update = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and
        $self->_refresh_project_tasks({ project_id => $update->{project_id} });

    return $update->{id};
}

sub move_tasks {
    my $self = shift;
    my $args = shift;

    my $to   = $args->{to}   || return;
    my $from = $args->{from} || return;

    $to =~ /$re_id/ or $to = $self->project_name2id($to) or return;

    for my $f ( keys %{ $from } ) {
        ref $from->{$f} eq 'ARRAY' or return;
        if ( $f !~ /$re_id/ ) {
            my $k = $self->project_name2id($f) or return;
            $from->{$k} = delete $from->{$f};
        }
    }

    my $result = $self->ua->post_form(
        "$base_url/moveItems",
        {
            token         => $self->token,
            project_items => encode_json $from,
            to_project    => $to,
        }
    );

    if ( $result->{status} == 200 ) {
        for ( $to, keys %{ $from } ) {
            $self->_refresh_project_tasks({ project_id => $_ });
        }
    }

    return $result->{status};
}

sub _optional_task_params {
    my $self = shift;
    my $args = shift;

    return (
      ( date_string => $args->{date_string} )x!! $args->{date_string},
      ( priority    => $args->{priority}    )x!! $args->{priority},
      ( indent      => $args->{indent}      )x!! $args->{indent},
      ( item_order  => $args->{item_order}  )x!! $args->{item_order},
    );
}

sub _optional_project_params {
    my $self = shift;
    my $args = shift;

    return (
        ( color  => $args->{color}  )x!! $args->{color},
        ( indent => $args->{indent} )x!! $args->{indent},
        ( order  => $args->{order}  )x!! $args->{order},
    );
}

sub project_name2id {
    my $self  = shift;
    my $name = shift;

    return $self->_name2project->{$name}{id};
}


1;

__END__

LEFT:

register
deleteUser
updateUser
+ updateAvatar

getAllCompletedItems
updateOrders
updateRecurringDate
completeItems
uncompleteItems

getNotificationSettings
updateNotificationSetting

? query

? uploadFile

??? getRedirectLink
????? LABELS STUFF (payed version)
????? NOTES  STUFF (payed version)

