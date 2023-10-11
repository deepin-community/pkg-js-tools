package Debian::PkgJs::Semver;

use strict;
use Exporter 'import';
use IO::Pipe;

our @EXPORT = ('semver');

my $_semver;

sub buildChannel {
    my $qchannel = IO::Pipe->new;
    my $rchannel = IO::Pipe->new;

    my $pid = fork;

    unless ($pid) {
        $| = 1;
        $qchannel->reader();
        $rchannel->writer();
        open STDIN,  '<&', $qchannel->fileno or die $!;
        open STDOUT, '>&', $rchannel->fileno or die $!;
        exec qq@node -e 'var readline=require("readline");
var semver=require("semver");
var rl=readline.createInterface({input:process.stdin,output:process.stdout,terminal:false});
rl.on("line",function(line){
  var v=line.replace(/ .*\$/,"");
  var r=line.replace(/^.* /,"");
  console.log(semver.satisfies(v,r)?1:0)
});
'@;
        exit;
    }

    # Initialize and verify semver channel
    $qchannel->writer();
    $rchannel->reader();
    $qchannel->autoflush(1);
    $qchannel->print("1.1.1 ^1.0.0\n");
    my $v = $rchannel->getline;
    chomp $v;
    if ( $v eq '1' ) {
        $_semver = sub {
            my ( $v, $ref ) = @_;
            chomp $v;
            chomp $ref;
            my $res;
            eval {
                $qchannel->print("$v $ref\n");
                $res = $rchannel->getline;
                chomp $res;
            };
            return $res;
        }
    }
    else {
        die "Unable to check versions, did you install node-semver ?\n";
    }
    
}

sub semver {
    buildChannel() unless $_semver;    
    return $_semver->(@_);
}

1;
