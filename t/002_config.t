use strict;
use Test::More;
use File::Temp ();
use Brahman::Config;

sub tempfile {
    my $fh = File::Temp->new(UNLINK => 1);
    print $fh $_[0];
    $fh->flush;
    $fh->seek(0, 0);
    return $fh;
}

subtest 'simple config' => sub {
    my $tempfile = tempfile(<<EOFILE);
[program:sample]
foo=1
bar=abcdef
baz=hogehoge
EOFILE
    my $config = Brahman::Config->read_file( $tempfile->filename );
    my $expected = {
        'program:sample' => {
            foo => 1,
            bar => 'abcdef',
            baz => 'hogehoge',
        }
    };
    if (! is_deeply $config, $expected, "config matches") {
        diag explain $config;
    }

};

subtest 'include' => sub {
    my $tempfile1 = tempfile(<<EOFILE);
[program:sample1]
foo=1
bar=abcdef
baz=hogehoge
EOFILE
    my $tempfile2 = tempfile(<<EOFILE);
[program:sample2]
foo=1
bar=abcdef
baz=hogehoge
EOFILE
    my $tempfile3 = tempfile(<<EOFILE);
[include]
files = $tempfile1 $tempfile2
EOFILE

    my $config = Brahman::Config->read_file( $tempfile3->filename );
    my $expected = {
        'program:sample1' => {
            foo => 1,
            bar => 'abcdef',
            baz => 'hogehoge',
        },
        'program:sample2' => {
            foo => 1,
            bar => 'abcdef',
            baz => 'hogehoge',
        }
    };
    if (! is_deeply $config, $expected, "config matches") {
        diag explain $config;
    }

};

done_testing;
