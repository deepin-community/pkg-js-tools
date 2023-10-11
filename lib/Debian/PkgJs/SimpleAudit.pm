package Debian::PkgJs::SimpleAudit;

use strict;
use Debian::PkgJs::Utils;
use Debian::PkgJs::Version;
use HTTP::Request::Common;
use LWP::UserAgent;
use Exporter 'import';
use JSON;

our @EXPORT = ('&advisories');

sub advisories {
    my ( $path, $version ) = @_;
    my $name;
    if ( defined $version ) {
        $name = $path;
    }
    else {
        my $tmp = pjson($path);
        $name    = $tmp->{name};
        $version = $tmp->{version};
    }
    my $data = qq["$name":"$version"];
    my $data =
qq[{"name":"npm_audit_test","version":"1.0","requires":{$data},"dependencies":{"$name":{"version":"$version"}}}];
    my $req = HTTP::Request->new( 'POST',
        'https://registry.npmjs.org/-/npm/v1/security/audits' );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content($data);
    my $resp = LWP::UserAgent->new()->request($req);
    my $res  = '';

    if ( $resp->is_success ) {
        my $json  = eval { JSON::from_json( $resp->decoded_content ) };
        my $count = 0;
        if ($json) {
            foreach my $adv ( keys %{ $json->{advisories} } ) {
                my $c = $json->{advisories}->{$adv};
                $res .= "$name $c->{vulnerable_versions}
Severity: $c->{severity}
$c->{title} - $c->{url}

";
                $count++;
            }
            $res .= "found $count vulnerabilities\n";
        }

        #print "RES: " . $res->decoded_content . "\n";
    }
    return $res;
}

1;
__END__
=head1 NAME

Debian::PkgJS::SimpleAudit - Perl module to get security advisories
from NPM registry

=head1 SYNOPSIS

  use Debian::PkgJS::SimpleAudit;
  
  my $audit = advisories('/path/to/nodejs/module');
  # OR
  my $audit = advisories('@babel/runtime', '0.7.16');
  
  if($audit) {
      print STDERR $audit;
      exit 1;
  }

=head1 DESCRIPTION

Debian::PkgJS::SimpleAudit provides a single function to get security
advisories from NPM registry.

=head2 EXPORT

=over

=item B<advisories()>

This function build a query to get all NPM security advisories for the
given JS module. It returns a string in the same format than "C<npm audit>"
I<(empty if no advisories are available)>.

B<advisories()> takes one or two arguments:

=over

=item B<advisories('/path/to/module')>: use name and version found in
package.json I<(or package.yaml)>.

=item B<advisories($name,$version)>: use given module name and version

=back

=back

=head1 COPYRIGHT AND LICENSE

Copyright Yadd E<lt>yadd@debian.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

On Debian systems, the complete text of version 2 of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-2'.
If not, see L<http://www.gnu.org/licenses/>.

=cut
