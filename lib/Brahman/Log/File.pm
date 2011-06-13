
package Brahman::Log::File;
use Mouse;
use IO::Handle;
use AnyEvent;

extends 'Brahman::Event::PubSub';

has logfile_size => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        (stat($self->logfile))[7];
    }
);

has logfile_maxbytes => (
    is => 'ro',
    default => 1024 ** 2
);

has logfile => (
    is => 'ro',
    required => 1,
);

has logfh => (
    is => 'rw',
    lazy => 1,
    builder => 'build_logfh'
);

sub build_logfh {
    my ($self) = @_;

    my $file = $self->logfile;
    open my $fh, '>>', $file
        or die "Failed to open $file: $!";
    $fh->autoflush(1);
    return $fh;
}

override consume => sub {
    my ($self, $object) = @_;
    # { type => $type, message => $message, time => $time, trace => $trace }

    my $size;
    my $maxbytes = $self->logfile_maxbytes;
    my $check_rotate = $maxbytes > 0;
    if ( $check_rotate ) {
        $size = $self->logfile_size;
    }

    my $message = sprintf "%s [%s] %s at %s\n",
        $object->{time} || scalar Time::HiRes::gettimeofday(),
        $object->{type} || 'UNKNOWN',
        $object->{message} || '(null)',
        $object->{trace}   || '(null)',
    ;
    my $fh = $self->logfh;
    print $fh $message;

    if ( $check_rotate ) {
        my $new_size = length($message) + $size;
        $self->logfile_size( $new_size );
        if ( $new_size >= $self->logfile_maxbytes ) {
            $self->rotatelog();
        } 
    }
};

sub rotatelog {
    my $self = shift;

    my $file = $self->logfile;
    my $max  = 10;
    my @files = sort { 
        (($b =~ /\.(\d+)$/))[0] <=> (($a =~ /\.(\d+)$/))[0]
    } grep { /\.\d+$/ } glob( "$file.*" );

    foreach my $oldfile ( @files ) {
        next unless $oldfile =~ /\.(\d+)$/;
        my $idx = $1;
        if ($idx >= $max) {
            unlink $oldfile;
        } else {
            rename $oldfile, "$file." . ( $idx + 1 )
        }
    }

    rename $file, "$file.1";
    $self->logfh($self->build_logfh);
}

sub spawn {
    my ($class, $name, %args) = @_;

    local $ENV{PERL5LIB} = join ":", @INC;
    exec {$^X}
        $^X,
        '-e' => 'require shift; Brahman::Log::File->bootstrap( map { ($_ => shift @ARGV) } qw(subscribe_connect logfile maxbytes backups) )',
        $INC{'Brahman/Log/File.pm'},
        map { defined $_ ? $_ : '' } 
            @args{ qw( subscribe_connect logfile maxbytes backups ) }
    ;
        
}

sub bootstrap {
    my ($class, %args) = @_;

    my $cv = AE::cv;
    my $logger = $class->new(%args, condvar => $cv);
    $logger->start;
    $cv->recv;
}

no Mouse;

1;