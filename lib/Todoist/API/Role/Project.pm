package Todoist::API::Role::Project;

use Moo::Role;
use Carp;

use List::Util    qw( first );
use JSON::MaybeXS qw( encode_json );

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

    return $self->GET({ cmd => 'getProjects' });
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

    return $self->GET({
        cmd    => 'getProject',
        params => "project_id=$id",
    });
}

sub add_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    exists $args->{name} or return;

    my $params = {
        name => $args->{name},
        $self->_optional_project_params($args),
    };

    my $add = $self->POST({
        cmd    => 'addProject',
        params => $params
    });

    ref $add and $self->_refresh_projects_attr();

    return $add->{id};
}

sub update_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $params = {
        project_id => $args->{id},
      ( name       => $args->{name} )x!! $args->{name},
        $self->_optional_project_params($args),
    };

    my $update = $self->POST({
        cmd    => 'updateProject',
        params => $params
    });

    ref $update and $self->_refresh_projects_attr();

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

    my $status = $self->POST({
        cmd         => 'updateProjectOrders',
        params      => { item_id_list => encode_json $ids },
        status_only => 1,
    });

    $status == 200 and $self->_refresh_projects_attr();

    return $status;
}

sub delete_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $status = $self->GET({
        cmd    => 'deleteProject',
        params => 'project_id=' . $args->{id},
        status_only => 1,
    });

    $status == 200 and $self->_refresh_projects_attr();

    return $status;
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

    $self->_project_add_id_if_name($args);

    my $id   = $args->{id};
    my $name = $args->{name};

    if ( ! $name ) {
        my $p = first { $_->{id} == $id } @{ $self->projects };
        $name = $p->{name};
    }

    my $tasks = $self->GET({
        cmd    => 'getUncompletedItems',
        params => "project_id=$id",
    });

    $self->_pname2tasks->{$name} = $tasks;
}

sub project_tasks {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    $self->_refresh_project_tasks({ id => $args->{id} });

    return $self->_pname2tasks->{ $args->{name} };
}

sub project_name2id {
    my $self  = shift;
    my $name = shift;

    return $self->_name2project->{$name}{id};
}

sub _project_add_id_if_name {
    my $self = shift;
    my $args = shift;

    !$args->{id} and $args->{name} and
        $args->{id} = $self->project_name2id( $args->{name} );

    !$args->{project_id} and $args->{project_name} and
        $args->{project_id} = $self->project_name2id( $args->{project_name} );
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
