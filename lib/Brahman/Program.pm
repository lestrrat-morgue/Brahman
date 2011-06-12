
# is_active && numprocs > # of procs
#   -> automatically spawn

package Brahman::Program;
use Mouse;
use Mouse::Util::TypeConstraints;
use Config ();
use Brahman::Event::Producer;
use IO::Handle;
use POSIX ();
use Time::HiRes ();

my %signo;
my @signame;
{
    my $i = 0;
    foreach my $name (split(' ', $Config::Config{sig_name})) {
        $signo{$name} = $i;
        $signame[$i] = $name;
        $i++;
    }
}

coerce 'Bool'
    => from 'Str'
    => via {
        /^true$/i ? 1 :
        /^false$/i ? 0 :
        $_
    }
;

has is_active => (
    is => 'rw',
    isa => 'Bool',
    lazy => 1,
    default => sub { shift->autostart },
);

has children => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} }
);

my %boolean = (
    autostart => 1,
    autorestart => 1,
    redirect_stderr => 0,
);
while ( my ($key, $default) = each %boolean ) {
    has $key => (
        is => 'ro',
        isa => 'Bool',
        default => $default,
        coerce => 1,
    );
}

foreach my $optional ( qw(directory uid umask environment) ) {
    has $optional => (
        is => 'ro'
    );
}

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has command => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has numprocs => (
    is => 'ro',
    isa => 'Int',
    default => 1,
);

subtype 'SignalName' => as 'Int';
coerce SignalName
    => from 'Str'
    => via { $signo{$_} }
;
has stopsignal => (
    is => 'ro',
    isa => 'SignalName',
    default => $signo{TERM},
    coerce => 1,
);

has stdout_logfile => (
    is => 'ro',
);

has log_publisher => (
    is => 'ro',
    default => sub {
        my $p = Brahman::Event::Producer->new(
            host => 'unix/',
            port => '/Users/daisuke/git/Dragonaut/event.sock'
        );
        $p->start;
        $p;
    }
);

sub want_start {
    my $self = shift;

    return
        $self->is_active &&
        $self->autorestart &&
        scalar keys %{$self->children} < $self->numprocs
    ;
}

sub terminate {
    my ($self, $pid) = @_;
    if ( $pid ) {
        kill $self->stopsignal, $pid;
    } else {
        my $children = $self->children;
        foreach my $pid ( keys %$children ) {
            kill $self->stopsignal, $pid;
        }
    }
}

sub reaped {
    my ($self, $pid) = @_;
    delete $self->children->{$pid};
}

sub make_logpipe {
    my $self = shift;

    my ($reader, $writer) = AnyEvent::Util::portable_pipe;

    my $log_publisher = $self->log_publisher;

    # Listen to the child process's STDOUT/STDERR
    my $hdl_reader = AnyEvent::Handle->new(fh => $reader);
    my $code; $code = sub {
        my ($hdl, $line) = @_;
        $log_publisher->publish( {
            type => "INFO",
            message => $line,
            time    => scalar Time::HiRes::gettimeofday()
        } );
        $hdl->push_read( line => $code );
    };

    $hdl_reader->push_read(line => $code);
    $hdl_reader->on_error( sub { $_[0]->destroy } );

    return ($hdl_reader, $reader, $writer);
}


sub start {
    my ($self, $ctxt) = @_;

    my ($stdout_hdl, $stdout_reader, $stdout_writer) = $self->make_logpipe();
    my ($stderr_hdl, $stderr_reader, $stderr_writer) = $self->make_logpipe();

    my $pid = fork();
    if (! defined $pid ) {
        warn "failed to fork $!";
        return;
    }

    if ($pid) { # parent
        $self->children->{$pid} = [ $stdout_hdl, $stderr_hdl ];
        $ctxt->watch_child( $pid, $self );
    } else {
        eval {
            local %ENV = %ENV;
            if ( my $env = $self->environment ) {
                my @env = map { split /=/, $_, 2 } split /,/, $env;
                while ( my ($env, $value) = splice @env, 0, 2 ) {
                    $ENV{ $env } = $value;
                }
            }

            open STDOUT, '>&' . fileno($stdout_writer)
                or die "Faile to redirect STDOUT to log publisher: $!";

            if ( $self->redirect_stderr ) {
                open STDERR, '>&STDOUT' or die $!;
            }

            STDOUT->autoflush(1);

            POSIX::setuid( $self->uid )  if $self->uid;
            CORE::chdir $self->directory if $self->directory;
            CORE::umask $self->umask     if $self->umask;

            print scalar localtime, " $$ Starting '", $self->command, "'\n";

            exec $self->command;
        };
        exit 1;
    }
}

no Mouse;

1;
