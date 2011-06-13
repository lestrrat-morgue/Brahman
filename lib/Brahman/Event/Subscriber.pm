package Brahman::Event::Subscriber;
use Mouse;
use AnyEvent::Handle;
use AnyEvent::Socket ();
use Scalar::Util ();

# subscribe_listen  => be a server, and wait for read
# subscribe_connect => be a client, and wait for read
has subscribe_listen  => ( is => 'ro' );
has subscribe_connect => ( is => 'ro' );

sub consume {}

sub accept_subscribe {
    my ($self, $fh) = @_;

    $self->{reader} = (sub {
        my $SELF = shift;
        Scalar::Util::weaken($SELF);
        return sub {
            my ($hdl, $object) = @_;
            $SELF->consume( $object );
            $hdl->push_read( json => $SELF->{reader} );
        };
    })->($self);

    my $hdl = AnyEvent::Handle->new(fh => $fh);
    $hdl->on_error( sub {
        my ($hdl) = @_;
        $hdl->destroy;
    } );

    $hdl->push_read(json => $self->{reader});
}

sub start {
    my $self = shift;
    my $accept = (sub {
        my ($SELF, $method) = @_;
        Scalar::Util::weaken($SELF);
        return sub {
            my $fh = shift;
            if (! $fh) {
                warn "something wrong @_";
                return;
            }
            $SELF->accept_subscribe( $fh );
        };
    })->($self);

    if ( my $listen = $self->subscribe_listen ) {
        my ($host, $port) = split /:/, $listen;
        AnyEvent::Socket::tcp_server( $host, $port, $accept );
    } elsif ( my $connect = $self->subscribe_connect ) {
        my ($host, $port) = split /:/, $connect;
        AnyEvent::Socket::tcp_connect( $host, $port, $accept );
    }
}

no Mouse;

1;
