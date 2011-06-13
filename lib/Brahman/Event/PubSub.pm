package Brahman::Event::PubSub;
use Mouse;
use AnyEvent::Handle;
use AnyEvent::Socket ();
use Scalar::Util ();

has subscribe_listen  => ( is => 'ro' );
has subscribe_connect => ( is => 'ro' );
has publish_listen    => ( is => 'ro' );
has publish_connect   => ( is => 'ro' );
has publisher         => ( is => 'rw' );

has condvar => (
    is => 'rw',
    default => sub { AnyEvent::CondVar->new }
);

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

sub start_pubsub {
    my $self = shift;

    # subscribe_listen  => be a server, and wait for read
    # subscribe_connect => be a client, and wait for read
    # publish_listen    => be a server, and wait for write 
    # publish_connect    => be a client, and wait for write

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

    # the writer does something a bit different
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