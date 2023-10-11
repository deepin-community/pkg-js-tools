use Test::More tests => 8;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/extlinks_extcopies";
$ENV{PATH} = "../../tools:$ENV{PATH}";
spawn( exec => [ 'dh', 'build', '--with', 'nodejs' ], wait_child => 1 );

ok( -d 'node_modules',             'node_modules created' );
ok( -d 'node_modules/@types',      'node_modules/@types created' );
ok( -l 'node_modules/@types/node', '@types/node linked' );
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
ok( !-e 'node_modules', 'node_modules removed' );

rename 'debian/nodejs/extlinks', 'debian/nodejs/extcopies';

spawn( exec => [ 'dh', 'build', '--with', 'nodejs' ], wait_child => 1 );
ok( -d 'node_modules',             'node_modules created' );
ok( -d 'node_modules/@types',      'node_modules/@types created' );
ok( -d 'node_modules/@types/node', '@types/node copied' );
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
ok( !-e 'node_modules', 'node_modules removed' );

rename 'debian/nodejs/extcopies', 'debian/nodejs/extlinks';
