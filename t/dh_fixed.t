use Test::More tests => 11;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/fixed";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn( exec => [ 'dh_auto_install', '--buildsystem=nodejs' ], wait_child => 1 );
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    debian/foo/usr/share/nodejs/foo/foo.js
    debian/foo/usr/share/nodejs/foo/lib/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/test.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/lib/bar.js
    )
)
{
    ok( ! -f $_, "$_ not installed" );
}
ok( -l 'debian/foo/usr/share/nodejs/foo/lib/foo.js', 'Link installed' );
ok( readlink('debian/foo/usr/share/nodejs/foo/lib/foo.js') eq 'index.js',
    'Good link value' );
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
chdir $pwd;
