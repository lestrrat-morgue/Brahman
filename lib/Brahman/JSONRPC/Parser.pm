package Brahman::JSONRPC::Parser;
use Mouse;
use Brahman::JSONRPC::Procedure;
use Carp ();
use Plack::Request;

has coder => (
    is => 'ro',
    required => 1,
);

sub construct_procedure {
    my $self = shift;
    Brahman::JSONRPC::Procedure->new( @_ );
}

sub construct_from_req {
    my ($self, $req) = @_;

    my $method = $req->method;
    my $proc;
    if ($method eq 'POST') {
        $proc = $self->construct_from_post_req( $req );
    } elsif ($method eq 'GET') {
        $proc = $self->construct_from_get_req( $req );
    } else {
        Carp::croak( "Invalid method: $method" );
    }

    return $proc;
}

sub construct_from_post_req {
    my ($self, $req) = @_;

    my $request = eval { $self->coder->decode( $req->content ) };
    if ($@) {
        Carp::croak( "Parse error" );
    }

    my $ref = ref $request;
    if ($ref ne 'ARRAY') {
        $request = [ $request ];
    }

    my @procs;
    foreach my $req ( @$request ) {
        Carp::croak( "Invalid parameter") unless ref $req eq 'HASH';
        push @procs, $self->construct_procedure(
            method => $req->{method},
            id     => $req->{id},
            params => $req->{params},
        );
    }
    return \@procs;
}

sub construct_from_get_req {
    my ($self, $req) = @_;

    my $params = $req->query_parameters;
    my $decoded_params;
    if ($params->{params}) {
        $decoded_params = eval { $self->coder->decode( $params->{params} ) };
    }
    return [
        $self->construct_procedure(
            method => $params->{method},
            id     => $params->{id},
            params => $decoded_params
        )
    ];
}

1;