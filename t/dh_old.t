use Test::More tests => 3;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/old";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn(
    exec       => [ 'fakeroot', 'dh_auto_install', '--buildsystem=nodejs' ],
    wait_child => 1
);
spawn( exec => [ 'fakeroot', 'dh_install' ], wait_child => 1 );

foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
