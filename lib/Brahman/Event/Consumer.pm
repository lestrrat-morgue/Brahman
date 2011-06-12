package Brahman::Event::Consumer;
use Mouse;
use AnyEvent::Handle;
use AnyEvent::Socket ();
use JSON ();
use Scalar::Util ();

has condvar => (
    is => 'ro',
    default => sub { AnyEvent::CondVar->new }
);

has host => (
    is => 'ro',
    required => 1,
);

has port => (
    is => 'ro',
    required => 1,
);

sub start {
    my $self = shift;

    $self->condvar->begin;
    AnyEvent::Socket::tcp_connect( $self->host, $self->port, sub {
        my ($fh, $host, $port) = @_;
        if (! $fh) {
            warn "Failed to connect";
            $self->condvar->end;
            return;
        }
        $self->register_producer( $fh );
    } );
}

sub register_producer {
    my ($self, $fh) = @_;

    Scalar::Util::weaken($self);
    $self->{reader} = sub {
        my ($hdl, $object) = @_;
        $self->consume( $object );
        $hdl->push_read( json => $self->{reader} );
    };

    my $hdl = AnyEvent::Handle->new(fh => $fh);
    $hdl->on_error( sub {
        my ($hdl) = @_;
        $self->condvar->end;
        $hdl->destroy;
    } );
    $hdl->push_read(json => $self->{reader});
}

sub consume {}

no Mouse;

1;