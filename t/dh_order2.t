use Test::More tests => 2;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/order2";

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
    $content eq 'two
one
three
', 'Order successful'
) or diag "Get: $content";
unlink 'order';

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
chdir $pwd;
