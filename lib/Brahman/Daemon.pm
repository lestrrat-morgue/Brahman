package Brahman::Daemon;
use Mouse;
use AnyEvent;
use Config::INI::Reader;
use Brahman::Program;
use Brahman::JSONRPC;
use POSIX();

has children => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} }
);

has is_looping => (
    is => 'rw',
    isa => 'Bool',
    default => 1,
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

sub read_config {
    my $self = shift;
    my $config = Config::INI::Reader->read_file( $self->config_file );

    my $programs = $self->programs;
    foreach my $o_name ( keys %$config ) {
        next unless $o_name =~ /^program:(.+)$/;
        my $name = $1;
        my $new = Brahman::Program->new( {
            name => $name,
            %{ $config->{$o_name} }
        } ) ;

        if ( my $old = $programs->{$name} ) {
            $old->reload( $new );
        } else {
            $programs->{$name} = $new;
        }
    }
    
}

has watchers => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} },
);
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
        $self->main_cv->end;
        $self->del_watcher( "child.$pid" );
    };

    $self->add_watcher( "child.$pid", $child );
}

has main_cv => ( 
    is => 'ro',
    isa => 'AnyEvent::CondVar',
    default => sub { AnyEvent::CondVar->new }
);

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
        # terminate the program
        my $program = $children->{$pid};
        if ($program) {
            $program->terminate;
        }
    }

    $self->main_cv->end;
}

sub run {
    my $self = shift;

    my $sighup  = AE::signal HUP => sub { $self->read_config };
    my $sigint  = AE::signal INT => sub { $self->stop() };
    my $spawn   = AE::timer 0, 1,  sub { $self->spawn_processes };
    my $jsonrpc = Brahman::JSONRPC->new( ctxt => $self );

    my $cv = $self->main_cv;
    $cv->cb( sub {
        undef $sighup;
        undef $sigint;
        undef $spawn;
        undef $jsonrpc;
    } );
    $cv->begin;

    $self->read_config;
    $jsonrpc->start;
    $cv->recv;
}

sub spawn_processes {
    my $self = shift;

    my $cv = $self->main_cv;
    my $programs = $self->programs;
    foreach my $name ( keys %{ $programs } ) {
        my $program = $programs->{$name};
        next unless $program->want_start;

        $program->start( $self );
        $cv->begin;
    }
}
        

1;