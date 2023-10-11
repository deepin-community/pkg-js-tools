package Debian::Debhelper::Buildsystem::nodejs_no_lerna;

use strict;
use Debian::Debhelper::Buildsystem::nodejs;
use Debian::PkgJs::Utils;
our @ISA = (qw(Debian::Debhelper::Buildsystem::nodejs));

$Debian::PkgJs::Utils::OPTS->{lerna} = 0;

1;
