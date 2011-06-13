package Brahman::Event::Publisher;
use Mouse;
use AnyEvent::Handle;
use AnyEvent::Socket ();
use Scalar::Util ();

# publish_listen    => be a server, and wait for write 
# publish_connect    => be a client, and wait for write
has publish_listen    => ( is => 'ro' );
has publish_connect   => ( is => 'ro' );
has publisher         => ( is => 'rw' );

sub start {
    my $self =shift;

    my $writer = (sub {
        my $SELF = shift;
        Scalar::Util::weaken($SELF);
        return sub {
            my $fh = shift;
            my $h = AnyEvent::Handle->new( fh => $fh );
            $h->on_error(sub {
                my ($hdl) = @_;
                $SELF->publisher(undef);
                $hdl->destroy;
            });
            $SELF->publisher( $h );
        }
    })->($self);

    if ( my $listen = $self->publish_listen ) {
        my ($host, $port) = split /:/, $listen;
        AnyEvent::Socket::tcp_server( $host, $port, $writer );
    } elsif ( my $connect = $self->publish_connect ) {
        my ($host, $port) = split /:/, $connect;
        AnyEvent::Socket::tcp_connect( $host, $port, $writer );
    }
}

sub publish {
    my ($self, $object) = @_;
    if ( my $hdl = $self->publisher ) {
        $hdl->push_write( json => $object );
    }
}

no Mouse;

1;
