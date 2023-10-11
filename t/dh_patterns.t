use Test::More tests => 17;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/patterns";
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
    debian/foo/usr/share/nodejs/foo/foo.js
    debian/foo/usr/share/nodejs/foo/lib/index.js
    debian/foo/usr/share/nodejs/foo/lib/a/index.js
    debian/foo/usr/share/nodejs/foo/lib/a/b/c/index.js
    debian/foo/usr/share/nodejs/foo/dst/css/a.css
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/test.js
    debian/foo/usr/share/nodejs/foo/partial/included
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/index.ts
    debian/foo/usr/share/nodejs/foo/lib/index.ts
    debian/foo/usr/share/nodejs/foo/lib/a/index.ts
    debian/foo/usr/share/nodejs/foo/lib/a/b/c/index.ts
    debian/foo/usr/share/nodejs/foo/partial/excluded
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
