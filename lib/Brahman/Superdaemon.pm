package Brahman::Superdaemon;
use Mouse;
use AnyEvent;
use Brahman::Config;
use Brahman::JSONRPC;
use Brahman::Supervisor;
use POSIX();

# pid of supervisors.
has children => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} }
);

has programs => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { +{} }
);

has config => (
    is => 'rw',
    isa => 'HashRef',
);

has config_file => (
    is => 'ro',
    isa => 'Str',
    default => "etc/config.ini",
    required => 1,
);

has condvar => ( 
    is => 'ro',
    isa => 'AnyEvent::CondVar',
    default => sub { AnyEvent::CondVar->new }
);

has state_dir => (
    is => 'ro',
    default => "/var/run/brahman"
);

has watchers => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} },
);

sub read_config {
    my $self = shift;
    my $config = Brahman::Config->read_file( $self->config_file );
    $self->config( $config );
}

sub spawn_supervisors {
    my $self = shift;
    my $config = $self->config;

    # create a reverse mapping
    my %map = reverse %{ $self->children };

    foreach my $o_name ( keys %$config ) {
        next unless $o_name =~ /^program:(.+)$/;
        my $name = $1;

        next if $map{ $name }; # already spawned
        $self->spawn_supervisor( $name );
    }
}

sub reap_supervisor {
    my ($self, $pid) = @_;
    delete $self->children->{$pid};
}

sub spawn_supervisor {
    my ($self, $name) = @_;

    Scalar::Util::weaken($self);
    my $pid = fork();
    if (! defined $pid) {
        die "Could not fork: $!";
    }

    if ($pid) {
        # parent
        $self->children->{$pid} = $name;
        my $w; $w = AE::child $pid, (sub {
            my $SELF  = shift;
            Scalar::Util::weaken($SELF);
            return sub {
                my $a_pid = shift;
                undef $w;
                $SELF->reap_supervisor($a_pid);
            }
        })->($self);
    } else {
        eval {
            Brahman::Supervisor->spawn(
                $name, 
                config_file => $self->config_file,
                state_dir => $self->state_dir
            );
        };
        exit 1;
    }
}

sub add_watcher { $_[0]->watchers->{ $_[1] } = $_[2] }
sub del_watcher { delete $_[0]->watchers->{ $_[1] } }

sub watch_child {
    my ($self, $pid, $cb) = @_;
    $self->children->{$pid} = $cb;
    my $child = AE::child $pid, sub {
        my ($pid, $status) = @_;

        if ( my $program = delete $self->children->{$pid} ) {
            $program->reaped($pid, $status);
        }
        $self->condvar->end;
        $self->del_watcher( "child.$pid" );
    };

    $self->add_watcher( "child.$pid", $child );
}

sub killproc {
    my ($self, $pid) = @_;
    if ( my $program = $self->children->{$pid} ) {
        $program->terminate($pid);
    }
}

sub stop {
    my $self = shift;

    my $children = $self->children;
    foreach my $pid ( keys %$children ) {
        # terminate supervisors
        kill POSIX::SIGTERM(), $pid;
    }

    $self->condvar->end;
}

sub spawn_processes {
    my $self = shift;

    my $cv = $self->condvar;

    my $programs = $self->programs;
    foreach my $name ( keys %{ $programs } ) {
        my $program = $programs->{$name};
        $program->start( $self );
        $cv->begin;
    }
}

sub run {
    my $self = shift;

    # Create a work directory to keep state. This state directory will
    # contain minimum information about the process' PID, and the how
    # it can be reached

    my $state_dir = $self->state_dir;
    if (! -e $state_dir) {
        require File::Path;
        if (! File::Path::make_path( $state_dir ) ) {
            die "Could not create state dir: $state_dir";
        }
    }

    my $sighup  = AE::signal HUP => sub {
        $self->read_config;
        $self->spawn_supervisors();
    };

    my $sigint  = AE::signal INT => sub { $self->stop() };
    my $spawn   = AE::timer 0, 1, sub { $self->spawn_supervisors };
    my $jsonrpc = Brahman::JSONRPC->new( ctxt => $self );

    my $cv = $self->condvar;
    $cv->cb( sub {
        undef $sighup;
        undef $sigint;
        undef $spawn;
        undef $jsonrpc;
    } );
    $cv->begin;

    $self->read_config;
    $self->spawn_supervisors();
    $jsonrpc->start;
}

1;