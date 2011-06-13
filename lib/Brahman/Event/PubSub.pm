package Brahman::Event::PubSub;
use Mouse;

extends qw(Brahman::Event::Publisher Brahman::Event::Subscriber);

override start => sub {
    my $self = shift;
    $self->Brahman::Event::Publisher::start(@_);
    $self->Brahman::Event::Subscriber::start(@_);
};

no Mouse;

1;