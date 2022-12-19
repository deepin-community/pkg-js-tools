package Debian::PkgJs::Banned;

use strict;

use Exporter 'import';

our @EXPORT = ('$BANNED');

our $BANNED = qr'^(?:request(?:-promise-core)?|g(?:yp-build|roove|dal)|s(?:tringprep|imple-is)|lodash-compat|cross-spawn)$'i;
