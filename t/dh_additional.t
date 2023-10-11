use Test::More tests => 28;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/additional";

# Configure step
spawn(
    exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
    wait_child => 1
);
ok( !-l 'node_modules/comp-one', 'comp-one/nolink' );
ok( -l 'node_modules/comp_two',  'Main link' );
ok( readlink('node_modules/comp_two') eq '../packages/comp-two', ' good link' );
ok( -l 'node_modules/comp-three',                                'Main link' );
ok( -l 'packages/comp-three/node_modules/comp_two', 'component_links' );
ok(
    readlink('packages/comp-three/node_modules/comp_two') eq
      '../../../packages/comp-two',
    ' good link'
);

# Build step
spawn( exec => [ 'dh_auto_build', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'comp-one/a', 'build creates comp-one/a' );
unlink 'comp-one/a';

# Test step
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');

# Install step
spawn(
    exec       => [ 'fakeroot', 'dh_auto_install', '--buildsystem=nodejs' ],
    wait_child => 1
);
unlink('comp-one/bar');

foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    debian/foo/usr/share/nodejs/comp-one/package.json
    debian/foo/usr/share/nodejs/comp-one/index.js
    debian/foo/usr/share/nodejs/comp_two/package.json
    debian/foo/usr/share/nodejs/comp_two/index.js
    debian/foo/usr/share/nodejs/comp-three/index.js
    debian/foo/usr/share/nodejs/comp-three/package.json
    debian/foo/usr/share/nodejs/comp-three/test.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/comp-one/test.js
    debian/foo/usr/share/nodejs/comp_two/tests.js
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}

if ( ok( -f 'debian/foo.substvars', 'Substvars file exists' ) ) {
    open my $f, '<', 'debian/foo.substvars';
    my ( $provides, $nodeVersion );
    while (<$f>) {
        if (/^nodejs:Provides=(.*)$/) {
            $provides = $1;
        }
        elsif (/^nodejs:Version=(.*)$/) {
            $nodeVersion = $1;
        }
    }
    close $f;
    ok( $provides,             'Found ${nodejs:Provides}' );
    ok( $nodeVersion,          "Found \${nodejs:Version}: $nodeVersion" );
    ok( $nodeVersion =~ /^\d/, '${nodejs:Version} starts with a digit' );
    my %h = map { /^(\S+)\s*\(=\s*(\S+)\s*\)$/; ( $1 => $2 ) } split /\s*,\s*/,
      $provides;
    my %ref = (
        'foo'        => '0.1',
        'comp-one'   => '0.1.1',
        'comp-two'   => '0.2',
        'comp-three' => '0.3.3',
    );
    foreach my $mod ( sort keys %ref ) {
        ok(
            delete( $h{"node-$mod"} ) eq $ref{$mod},
            "Found node-$mod (= $ref{$mod})"
        );
    }
    ok( !%h, 'No other values found' );
}

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
