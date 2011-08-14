
package Brahman::Supervisor;
use Mouse;
use AnyEvent;
use AnyEvent::Handle;
use Brahman::Config;
use Brahman::Program;
use Brahman::Log::File;
use File::Copy ();
use File::Temp ();
use JSON ();

extends 'Brahman::Event::PubSub';

has name => (
    is => 'ro',
    required => 1,
);

has config_file => (
    is => 'ro',
    required => 1,
);

has program_pids => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} }
);

has logger_pids => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} }
);

has program => (
    is => 'rw',
);

has state_dir => (
    is => 'ro',
    required => 1,
);

has condvar => (
    is => 'ro',
    default => sub { AnyEvent::CondVar->new }
);

has publish_listen => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $name = $self->name;
        my $sock = File::Spec->catfile( $self->state_dir, "$name.publish.sock" );
        "unix/:$sock"
    }
);

override consume => sub {
    my ($self, $object) = @_;

    my $cmd = $object->{cmd} || '';
    if ( $cmd eq 'config' ) {
        $self->program( Brahman::Program->new( $object->{payload} ) );
    }
};

sub bootstrap {
    my ($class, %args) = @_;
    my $supervisor = $class->new(%args);
    $supervisor->run;
    $supervisor->condvar->recv;
}

sub spawn {
    my ($class, $name, %args) = @_;

    local $ENV{PERL5LIB} = join ":", @INC;
    exec {$^X}
        $^X,
        '-e' => 'require shift; Brahman::Supervisor->bootstrap(map { ($_ => shift @ARGV) } qw(name state_dir config_file) )',
        $INC{'Brahman/Supervisor.pm'},
        $name,
        map { defined $_ ? $_ : '' }
            @args{ qw(state_dir config_file) }
    ;
}

has state_file => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        File::Spec->catfile( $self->state_dir, $self->name . ".json" );
    }
);

sub record_state {
    my $self = shift;

    my $program_pids = $self->program_pids || {};
    my $file = $self->state_file;
    my $temp = File::Temp->new(UNLINK => 1);
    print $temp JSON->new->utf8->pretty->encode(
        {
            subscribe_listen => $self->subscribe_listen,
            subscribe_connect => $self->subscribe_connect,
            publish_listen => $self->publish_listen,
            publish_connect => $self->publish_connect,
            pid => $$,
            processes => [
                map {
                    +{
                        pid => $_,
                        since => $program_pids->{$_}->[0],
                    }
                } keys %$program_pids
            ],
        }
    );

    $temp->close;
    File::Copy::copy( $temp->filename, $file );
}

sub read_config {
    my $self = shift;

    my $name = $self->name;
    my $config = Brahman::Config->read_file( $self->config_file );
    my $this_config = $config->{"program:$name"};

    $self->program(
        Brahman::Program->new(
            {
                name => $name,
                %{ $this_config || {} },
            }
        )
    );
}

sub run {
    my $self = shift;

    $self->read_config();
    $self->start;

    # record where we're listening
    $self->record_state();

    # start the event consumer.
    my $spawn_program = AE::timer 0, 1, sub { $self->spawn_program };
    my $spawn_logger  = AE::timer 0, 1, sub { $self->spawn_logger };
    my $sigint = AE::signal INT => sub { $self->stop() };

    my $cv = $self->condvar;
    $cv->cb( sub {
        undef $sigint;
        undef $spawn_program;
        undef $spawn_logger;
    } );

    $cv->begin;
}

sub stop {
    my $self = shift;

    # terminate the program
    if ( my $program = $self->program ) {
        $program->terminate();
    }
    $self->condvar->end;
}

sub spawn_logger {
    my $self = shift;
    my $program = $self->program;

    return unless $program;

    my $publish_listen = $self->publish_listen;
    my $logger_pids    = $self->logger_pids;
    my %stream2pid     = ( reverse %$logger_pids );
    foreach my $stream ( qw(stdout stderr) ) {
        next if $stream2pid{$stream};

        my $logfile_method  = "${stream}_logfile";
        my $maxbytes_method = "${stream}_logfile_maxbytes";
        my $backups_method  = "${stream}_logfile_backups";

        my $logfile  = $program->$logfile_method;
        my $maxbytes = $program->$maxbytes_method;
        my $backups  = $program->$backups_method;

        next unless $logfile;

        my $pid = fork();
        if (! defined $pid) {
            die "Could not fork: $!";
        }

        if ( $pid ) {
            my $w; $w = AE::child $pid, (sub {
                my $SELF = shift;
                Scalar::Util::weaken($SELF);
                return sub {
                    my $a_pid = shift;
                    if ($SELF->logger_pids->{$a_pid} eq $stream) {
                        delete $SELF->logger_pids->{$a_pid};
                    }
                }
            })->($self);
            $logger_pids->{$pid} = $stream;
        } else {
            eval {
                Brahman::Log::File->spawn(
                    $self->program->name,
                    subscribe_connect => $publish_listen,
                    logfile           => $logfile,
                    maxbytes          => $maxbytes,
                    backups           => $backups,
                );
            };
            warn $@ if $@;
            exit 1;
        }
    }
}


sub spawn_program {
    my $self = shift;
    my $program = $self->program;

    return unless $program;
    return unless $program->want_start( scalar keys %{ $self->program_pids } );

    my ($stdout_hdl, $stdout_reader, $stdout_writer) = $self->make_logpipe();
    my ($stderr_hdl, $stderr_reader, $stderr_writer) = $self->make_logpipe();

    my $pid = $program->start( $stdout_writer, $stderr_writer );
    $self->condvar->begin;

    $self->program_pids->{$pid} = [ time(), $stdout_hdl, $stderr_hdl ];

    my $w; $w = AE::child $pid, (sub {
        my $SELF = shift;
        Scalar::Util::weaken($SELF);
        return sub {
            my $a_pid = shift;
            undef $w;
            if (delete $SELF->program_pids->{$a_pid}) {
                $SELF->condvar->end;
            }
        }
    })->($self);

    $self->record_state();
}

sub make_logpipe {
    my $self = shift;

    my ($reader, $writer) = AnyEvent::Util::portable_pipe;

    # Listen to the child process's STDOUT/STDERR
    my $hdl_reader = AnyEvent::Handle->new(fh => $reader);
    my $code; $code = (sub {
        my $SELF = shift;
        Scalar::Util::weaken($SELF);
        return sub {
            my ($hdl, $line) = @_;
            $SELF->publish( {
                type => "INFO",
                message => $line,
                time    => scalar Time::HiRes::gettimeofday()
            } );
            $hdl->push_read( line => $code );
        };
    })->($self);

    $hdl_reader->push_read(line => $code);
    $hdl_reader->on_error( sub { $_[0]->destroy } );

    return ($hdl_reader, $reader, $writer);
}

no Mouse;

1;


__END__

# supervise a program, and also open proper listening socket for log collector
# programs. If appropriate, spawn log workers too

Basically, this is the Server::Starter of brahman programs
the supervisor has a listen socket where loggers can attach to.
exec'ed programs are given a pipe to talk to the supervisor.



