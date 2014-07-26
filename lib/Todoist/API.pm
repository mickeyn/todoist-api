package Todoist::API;

use Moo;
use Carp;

use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS  qw( decode_json encode_json );
use List::Util     qw( first );
use Todoist::Utils qw( read_password );

my $base_url = 'https://api.todoist.com/API';

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

sub login {
    my $self = shift;

    my $passwd = read_password();

    my $result = $self->ua->post_form(
        "$base_url/login",
        { email => $self->email, password => $passwd }
    );
    undef $passwd;

    my $decoded_result;
    try   { $decoded_result = decode_json $result->{content} }
    catch { croak 'login failed' };

    return $decoded_result;
}

sub token {
    my $self = shift;

    return $self->td_user->{api_token};
}

sub project {
    my $self = shift;
    my $name = shift || return;

    my $id = $self->_project_n2id($name);

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

    exists $args->{name} or return;

    my $params = {
        token => $self->token,
        name  => $args->{name},
        ( color  => $args->{color}  )x!! $args->{color},
        ( indent => $args->{indent} )x!! $args->{indent},
        ( order  => $args->{order}  )x!! $args->{order},
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

sub delete_project {
    my $self = shift;
    my $pid  = shift;

    (!ref $pid and $pid =~ /^[0-9]+$/) or return;

    my $result = $self->ua->get(
        sprintf("$base_url/deleteProject?token=%s&project_id=%d", $self->token, $pid)
    );

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $result->{status};
}

sub _refresh_projects_attr {
    my $self = shift;

    $self->_clear_name2project;
    $self->_clear_projects;
}

sub _refresh_project_tasks {
    my $self = shift;
    my $args = shift;

    my $pname = $args->{project_name};
    my $pid   = $args->{project_id};
    $pname or $pid or return;

    $pid   ||= $self->_project_n2id($pname);
    $pname ||= first { $_->{id} == $pid } @{ $self->projects };

    my $result = $self->ua->get(
        sprintf("$base_url/getUncompletedItems?token=%s&project_id=%d", $self->token, $pid)
    );

    my $tasks;
    try   { $tasks = decode_json( $result->{content} ) }
    catch { return +{} };

    $self->_pname2tasks->{$pname} = $tasks;
}

sub project_tasks {
    my $self  = shift;
    my $pname = shift;

    $self->_refresh_project_tasks({ project_name => $pname });

    return $self->_pname2tasks->{$pname};
}

sub add_task {
    my $self = shift;
    my $args = shift;

    exists $args->{content} or return;

    my $pid = $args->{project_id};
    if ( ! $pid ) {
        $args->{project_name} ||= 'Inbox';
        $pid = $self->_project_n2id( $args->{project_name} );
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

    (!ref $id and $id =~ /^[0-9]+$/) or return;

    return $self->delete_tasks([ $id ]);
}

sub delete_tasks {
    my $self = shift;
    my $ids  = shift;

    (ref $ids eq 'ARRAY' and @$ids > 0) or return;

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

sub _project_n2id {
    my $self  = shift;
    my $pname = shift;

    return $self->_name2project->{$pname}{id};
}


1;
