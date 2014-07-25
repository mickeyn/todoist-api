package Todoist::API;

use Moo;
use Carp;

use Todoist::Utils qw( read_password );

use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS qw( decode_json );

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
);

has _name2project => (
    is      => 'rw',
    isa     => sub { ref $_[0] eq 'HASH' or croak "wrong type for projects" },
    lazy    => 1,
    builder => '_build_name2project',
);

has _tasks => (
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

    my $id = $self->_name2project->{$name}{id};

    my $result = $self->ua->get(
        sprintf("$base_url/getProject?token=%s&project_id=%d", $self->token, $id)
    );

    my $project;
    try   { $project = decode_json( $result->{content} ) }
    catch { return +{} };

    return $project;
}

sub project_tasks {
    my $self  = shift;
    my $pname = shift;

    my $pid = $self->_name2project->{$pname}{id};

    my $result = $self->ua->get(
        sprintf("$base_url/getUncompletedItems?token=%s&project_id=%d", $self->token, $pid)
    );

    my $tasks;
    try   { $tasks = decode_json( $result->{content} ) }
    catch { return +{} };

    return $tasks;
}

sub add_task {
    my $self = shift;
    my $args = shift;

    exists $args->{content} or return;

    my $pid = exists $args->{project_name}
        ? $self->_name2project->{ $args->{project_name} }{id}
        : undef;

    my $params = {
        token   => $self->token,
        content => $args->{content},
      ( project_id  => $pid                 )x!! $pid,
      ( date_string => $args->{date_string} )x!! $args->{date_string},
      ( priority    => $args->{priority}    )x!! $args->{priority},
      ( indent      => $args->{indent}      )x!! $args->{indent},
      ( item_order  => $args->{item_order}  )x!! $args->{item_order},
    };

    return
        $self->ua->post_form(
            "$base_url/addItem",
            $params
        );
}

1;
