
# is_active && numprocs > # of procs
#   -> automatically spawn

package Brahman::Program;
use Mouse;
use Mouse::Util::TypeConstraints;
use Config ();
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

foreach my $stream ( qw(stdout stderr) ) {
    has "${stream}_logfile" => ( is => 'ro' );
    has "${stream}_logfile_maxbytes" => ( is => 'ro' );
    has "${stream}_logfile_backups" => (
        is => 'ro',
        default => 10,
    );
}

sub want_start {
    my ($self, $num_children) = @_;

    return
        $self->is_active &&
        $self->autorestart &&
        $num_children < $self->numprocs
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

sub start {
    my ($self, $stdout, $stderr) = @_;

    my $pid = fork();
    if (! defined $pid ) {
        warn "failed to fork $!";
        return;
    }

    if ($pid) { # parent
        return $pid;
    } else {
        eval {
            local %ENV = %ENV;
            if ( my $env = $self->environment ) {
                my @env = map { split /=/, $_, 2 } split /,/, $env;
                while ( my ($env, $value) = splice @env, 0, 2 ) {
                    $ENV{ $env } = $value;
                }
            }

            open STDOUT, '>&' . fileno($stdout)
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
