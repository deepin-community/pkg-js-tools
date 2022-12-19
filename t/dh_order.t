use Test::More tests => 2;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/order";

# Configure step
spawn(
    exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
    wait_child => 1
);

# Build step
spawn( exec => [ 'dh_auto_build', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'order', 'Build' );
open my $f, 'order' or die $!;
my $content = join '', <$f>;
close $f;
ok(
    $content eq 'three
one
two
', 'Order successful'
) or diag "Get: $content";
unlink 'order';

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
chdir $pwd;
