package Todoist::API::Project;

use Moo::Role;

use Carp;
use Try::Tiny;
use List::Util    qw( first );
use JSON::MaybeXS qw( decode_json encode_json );

my $re_num = qr/^[0-9]+$/;

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

sub _build_projects {
    my $self = shift;

    my $result = $self->ua->get(
        $self->base_url . "/getProjects?token=" . $self->token
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

sub project {
    my $self = shift;
    my $name = shift || return;

    my $id = $self->project_name2id($name);

    my $result = $self->ua->get(
        sprintf("%s/getProject?token=%s&project_id=%d", $self->base_url, $self->token, $id)
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
        $self->base_url . "/addProject",
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
        $self->base_url . "/updateProject",
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
        /$re_num/ or $_ = $self->project_name2id($_) or return;
    }

    my $result = $self->ua->post_form(
        $self->base_url . "/updateProjectOrders",
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
        sprintf("%s/deleteProject?token=%s&project_id=%d",
                $self->base_url, $self->token, $args->{id})
    );

    $result->{status} == 200 and $self->_refresh_projects_attr();

    return $result->{status};
}

sub _refresh_projects_attr {
    my $self = shift;

    $self->_clear_name2project;
    $self->_clear_projects;
}

sub _refresh_all_projects_tasks {
    my $self = shift;

    $self->_pname2tasks( +{} ); # clear

    for ( @{ $self->projects } ) {
        $self->_refresh_project_tasks({ id => $_->{id} });
    }
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
        sprintf("%s/getUncompletedItems?token=%s&project_id=%d",
                $self->base_url, $self->token, $id)
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

sub project_name2id {
    my $self  = shift;
    my $name = shift;

    return $self->_name2project->{$name}{id};
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


1;
