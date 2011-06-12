package Brahman::Event::Producer;
use Mouse;
use AnyEvent::Handle;
use AnyEvent::Socket ();

has host => (
    is => 'ro',
    required => 1,
);

has port => (
    is => 'ro',
    required => 1,
);

has handle => (
    is => 'rw',
);

sub start {
    my $self = shift;

    AnyEvent::Socket::tcp_server( $self->host, $self->port, sub {
        my $fh = shift;
        if ($fh) {
            $self->register_consumer( $fh );
        }
    } );
}

sub register_consumer {
    my ($self, $fh) = @_;

    my $h = AnyEvent::Handle->new( fh => $fh );
    $h->on_error(sub {
        my ($hdl) = @_;
        $self->handle(undef);
        $hdl->destroy;
    });
    $self->handle( $h );
}

sub publish {
    my ($self, $object) = @_;
    if ( my $hdl = $self->handle ) {
        $hdl->push_write( json => $object );
    }
}

no Mouse;

1;