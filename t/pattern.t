use Test::More;

my $pwd = `pwd`;
@tests = (
    'lib/*.js'                => 'index.js'           => 0,
    'lib/*.js'                => 'lib/index.js'       => 1,
    'lib/*.js'                => 'lib/a/index.js'     => 0,
    'lib/**/*.js'             => 'index.js'           => 0,
    'lib/**/*.js'             => 'lib/index.js'       => 1,
    'lib/**/*.js'             => 'lib/index.ts'       => 0,
    'lib/**/*.js'             => 'lib/a/index.js'     => 1,
    'lib/**/*.js'             => 'lib/a/b/c/index.js' => 1,
    'lib/**/*.js'             => 'lib/a/b/c/index.ts' => 0,
    'lib/**/*'                => 'index.js'           => 0,
    'lib/**/*'                => 'lib/index'          => 1,
    'lib/.e*'                 => 'lib/.es.js'         => 1,
    'lib/.e*'                 => 'lib/aes.xs'         => 0,
    'lib/.e*'                 => 'lib/.xs.js'         => 0,
    'lib/a*b/**/*.js'         => 'lib/acb/i.js'       => 1,
    'lib/a*b/**/*.js'         => 'lib/ab/i.js'        => 1,
    'lib/a*b/**/*.js'         => 'lib/acb/a/i.js'     => 1,
    'lib/a*b/**/*.js'         => 'lib/ac/a/i.js'      => 0,
    'lib/a*/*.js'             => 'lib/ac/a/i.js'      => 0,
    'lib/{*.css,xx}'          => 'lib/a.css'          => 1,
    'lib/{*.css,xx}'          => 'lib/xx'             => 1,
    'lib/{*.css,xx}'          => 'lib/xxx'            => 0,
    'lib/{*.css,xx}'          => 'lib/a.js'           => 0,
    'lib/{css,js}'            => 'lib/css'            => 1,
    'lib/a{css,js}'           => 'lib/acss'           => 1,
    'lib/{css,js}/*.js'       => 'lib/css/a.js'       => 1,
    'lib/{css,js}/*.js'       => 'lib/css/a/b.js'     => 0,
    'lib/{css,js}/**/*.js'    => 'lib/css/a/b/c.js'   => 1,
    'lib/{css,js}/**/*.js'    => 'lib/css/a/b/c.css'  => 0,
    'lib/**/{css,js}/*.js'    => 'lib/a/b/css/c.js'   => 1,
    'lib/**/{css,js}/*.js'    => 'lib/css/c.js'       => 1,
    'bin/*mocha*'             => 'bin/mocha.js'       => 1,
    'bin/*mocha*'             => 'bin/_mocha'         => 1,
    'out/{bench,tests}/**.js' => 'out/tests/index.js' => 1,
    'out/{bench,tests}'       => 'out/tests/index.js' => 1,
    'out/{bench,tests}'       => 'out/index.js'       => 0,

    # NB: "./" is added here since this is the behavior of nodejs.pm
    '*.*(c)[tj]s*' => './index.cjs'    => 1,
    '*.*(c)[tj]s*' => './index.cts'    => 1,
    '*.*(c)[tj]s*' => './index.js'     => 1,
    '*.*(c)[tj]s*' => './index.ts'     => 1,
    '**/*'         => './index.js'     => 1,
    '**/*'         => './lib/index.js' => 1,
    '**/*.js'      => './index.js'     => 1,
    '**/*.js'      => './lib/index.js' => 1,
    '**/*.js'      => './lib/index.ts' => 0,
);

plan tests => @tests / 3 + 2;

use_ok('Debian::Debhelper::Buildsystem::nodejs');

my $self;
ok( $self = Debian::Debhelper::Buildsystem::nodejs->new, 'New object' );

while (@tests) {
    my $expr   = shift @tests;
    my $file   = shift @tests;
    my $expect = shift @tests;
    ptest( $expr, $file, $expect );
}

sub ptest {
    my ( $expr, $file, $expect ) = @_;
    my ( $p, $pattern ) = $self->pattern($expr);
    ok(
        ( ( $file =~ $pattern and $file =~ /^$p/ ) xor !$expect ),
        "File $file " . ( $expect ? 'accepted' : 'rejected' ) . " by $expr"
    );
}
