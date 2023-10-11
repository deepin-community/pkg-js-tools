use Test::More tests => 7;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/fixed2";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn(
    exec       => [ 'fakeroot', 'dh_auto_install', '--buildsystem=nodejs' ],
    wait_child => 1
);

foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    debian/foo/usr/share/nodejs/foo/lib/foo.js
    debian/foo/xx/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/index.js
    debian/foo/usr/share/nodejs/zz/test.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
