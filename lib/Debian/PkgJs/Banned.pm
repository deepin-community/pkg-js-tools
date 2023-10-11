package Debian::PkgJs::Banned;

use strict;

use Exporter 'import';

our @EXPORT = ('&banned');

our $BANNED = {

    # Dangerous and useless (cross-platform)
    'cross-spawn' => 975942,

    # Buggy
    gdal => 992527,

    # Should not be used as reverse-dependency in Debian (stores pre-build
    # binaries). Use simply gyp instead
    'gyp-build' => 979475,

    # Unmaintained
    'lodash-compat'     => 'Useless',
    request             => 'npm',
    'request-promise.*' => 'Depends on request',

    # replaced by @mdn/browser-compat-data
    'mdn-browser-compat-data' => 'Replaced by @mdn/browser-compat-data',

    # replaced by @rollup/plugin-*
'rollup-plugin-(?:d(?:ynamic-import-vars|ata-uri|sv)|(?:(?:ht|ya)m|graphq|virtua|ur)l|(?:pluginutil|commonj)s|(?:multi-entr|legac)y|a(?:uto-install|lias)|(?:typescrip|eslin)t|b(?:abel|uble|eep)|s(?:ucrase|trip)|i(?:nject|mage)|r(?:eplace|un)|node-resolve|json|wasm)'
      => 'Replaced by @rollup/plugin-$1',

    # does not work on linux
    'fsevents' => 'not compatible with linux',

    # Renamed
    lolex => 'renamed to @sinonjs/fake-timers',
};

sub banned {
    my ($package) = pop;
    my $reason;
    foreach ( keys %$BANNED ) {
        if ( $package =~ /^$_$/ ) {
            my $match = $1;
            $reason = $BANNED->{$_};
            $reason =~ s/\$1/$match/g;
            if ( $reason eq 'npm' ) {
                $reason = "see https://www.npmjs.com/package/$package";
            }
            elsif ( $reason =~ /^#?(\d+)$/ ) {
                $reason = "see https://bugs.debian.org/$1";
            }
        }
    }
    return $reason;
}

1;
