
package Brahman::JSONRPC;
use Mouse;
use Class::Load ();
use Brahman::Constants qw(:all);
use Brahman::JSONRPC::Parser;
use JSON ();
use Plack::Request;
use Router::Simple;
use Scalar::Util ();
use Try::Tiny;
use Twiggy::Server;

has pid    => ( is => 'ro', default => $$ );
has ctxt   => ( is => 'ro', required => 1 );
has server => ( is => 'rw' );
has handlers => (
    is => 'ro',
    default => sub { +{} }
);
has coder  => (
    is => 'ro',
    default => sub { JSON->new->utf8 }
);
has parser => (
    is => 'ro',
    lazy => 1,
    default => sub {
        Brahman::JSONRPC::Parser->new(coder => $_[0]->coder);
    }
);

has router => (
    is => 'ro',
    default => sub {
        Router::Simple->new
    }
);

sub start {
    my $self = shift;
warn "start";
    my $http = Twiggy::Server->new(listen => [ "0.0.0.0:9999" ] );

    # weak ref?
    $http->register_service( $self->_jsonrpc_app );
    $self->server( $http );
}

sub BUILD {
    my $self = shift;

    my $router = $self->router;

    my %program_routes = (
        list => "list",
        kill => "killproc",
        activate => "activate",
        deactivate => "deactivate",
    );
    while ( my ($route, $action) = each %program_routes ) {
        $router->connect( $route, {
            handler => 'Program',
            action  => $action
        });
    }

    $router->connect("stop", {
        handler => 'Daemon',
        action  => 'stop',
    });

    return $self;
}

sub DEMOLISH {
    my $self = shift;
    if ( $self->pid == $$ ) {
        $self->server->{exit_guard}->end;
    }
}

sub _jsonrpc_app {
    my $self = shift;;
    Scalar::Util::weaken( $self );
    return sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        if ( $req->path_info !~ m{/rpc/?$} ) {
            return [ 404, [], [] ];
        }
        $self->dispatch_jsonrpc($req)
    };
}

sub guess_handler_class {
    my ($self, $klass) = @_;
    return join '::', Scalar::Util::blessed($self), 'Handler', $klass;
}

sub construct_handler {
    my ($self, $klass) = @_;

    my $handler = $self->handlers->{ $klass };
    if (! $handler) {
        Class::Load::load_class( $klass );
        $handler = $klass->new();
        if (! $handler->isa( 'Brahman::JSONRPC::Handler' ) ) {
            Carp::croak( "$klass does not implement Brahman::JSONRPC::Handler" );
        }
        $self->handlers->{$klass} = $handler;
    }
    return $handler;
}

sub get_handler {
    my ($self, $klass) = @_;

    if ($klass !~ s/^\+//) {
        $klass = $self->guess_handler_class( $klass );
    }

    my $handler = $self->construct_handler( $klass );
    if (BRAHMAN_JSONRPC_DEBUG) {
        warn "$klass -> $handler";
    }
    return $handler;
}


sub dispatch_jsonrpc {
    my ($self, $req) = @_;
    my @response;
    my $procedures;

    try {
        $procedures = $self->parser->construct_from_req( $req );
        if (@$procedures <= 0) {
            push @response, {
                error => {
                    code => RPC_INVALID_REQUEST,
                    message => "Could not find any procedures"
                }
            };
        }
    } catch {
        my $e = $_;
        if (BRAHMAN_JSONRPC_DEBUG) {
            warn "error while creating jsonrpc request: $e";
        }
        if ($e =~ /Invalid parameter/) {
            push @response, {
                error => {
                    code => RPC_INVALID_PARAMS,
                    message => "Invalid parameters",
                }
            };
        } elsif ( $e =~ /Parse error/ ) {
            push @response, {
                error => {
                    code => RPC_PARSE_ERROR,
                    message => "Failed to parse json",
                }
            };
        } else {
            push @response, {
                error => {
                    code => RPC_INVALID_REQUEST,
                    message => $e
                }
            }
        }
    };

    my $router = $self->router;
    foreach my $procedure (@$procedures) {
        if ( ! $procedure->{method} ) {
            my $message = "Procedure name not given";
            if (BRAHMAN_JSONRPC_DEBUG) {
                warn $message;
            }
            push @response, {
                error => {
                    code => RPC_METHOD_NOT_FOUND,
                    message => $message,
                }
            };
            next;
        }

        my $matched = $router->match( $procedure->{method} );
        if (! $matched) {
            my $message = "Procedure '$procedure->{method}' not found";
            if (BRAHMAN_JSONRPC_DEBUG) {
                warn $message;
            }
            push @response, {
                error => {
                    code => RPC_METHOD_NOT_FOUND,
                    message => $message,
                }
            };
            next;
        }

        my $action = $matched->{action};
        try {
            if (BRAHMAN_JSONRPC_DEBUG) {
                warn "Procedure '$procedure->{method}' maps to action $action";
            }

            my $handler = $self->get_handler( $matched->{handler} );
            my $result = $handler->execute( $self->ctxt, $action, $procedure );

            push @response, {
                jsonrpc => '2.0',
                result  => $result,
                id      => $procedure->id,
            };
        } catch {
            my $e = $_;
            if (BRAHMAN_JSONRPC_DEBUG) {
                warn "Error while executing $action: $e";
            }
            push @response, {
                error => {
                    code => RPC_INTERNAL_ERROR,
                    message => $e,
                }
            };
        };
    }

    my $res = $req->new_response(200);
    $res->content_type( 'application/json; charset=utf8' );
    if ( @response ) {
        try {
            my $json = $self->coder->encode( @$procedures > 1 ? \@response : $response[0] );
            $res->body( $json );
        } catch {
            $res->body( $_ );
        };
            
    }

    return $res->finalize;

}

no Try::Tiny;
no Mouse;

1;
