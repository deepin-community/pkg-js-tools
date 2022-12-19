# pkg-js/no-testsuite -- lintian check script for detecting a bad debian/watch configuration

package Lintian::Check::PkgJs::Repo;

use strict;
use warnings;
use Dpkg::IPC;
use Moo;
use namespace::clean;

with 'Lintian::Check';

sub source {
    my ( $self ) = @_;
    my ( $out, $err );
    return unless ( -e 'package.json' );
    spawn(
        exec            => ['debcheck-node-repo'],
        to_string       => \$out,
        error_to_string => \$err,
        wait_child      => 1,
        nocheck         => 1
    );
    $self->tag('inconsistency-debian-watch') if $?;
}

1;
