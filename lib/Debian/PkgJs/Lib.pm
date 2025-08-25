package Debian::PkgJs::Lib;

use strict;
use warnings;
use Dpkg::IPC;
use Dpkg::Version;
use LWP::UserAgent;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
  &uscanResult &url_part &git_last_version &git_watch &registry_watch
);

our $VERSION = '0.8.14';

sub uscanResult {
    unless ( -r 'debian/watch' ) {
        print STDERR "No debian/watch found\n";
        sleep 1;
        return ( undef, undef );
    }
    my ( $err, $out );
    spawn(
        exec            => [qw(uscan --report --dehs)],
        to_string       => \$out,
        error_to_string => \$err,
        wait_child      => 1,
        nocheck         => 1,
        timeout         => 30,
    );
    my %data;
    foreach (qw(upstream-url upstream-version)) {
        if ( $out =~ m#<$_>(.+?)</$_># ) {
            $data{$_} = $1;
        }
        else {
            print STDERR "Uscan failed\n";
            return;
        }
    }
    $data{'upstream-version'} =~ s/\+.*$// if $data{'upstream-version'};
    return ( $data{'upstream-version'}, $data{'upstream-url'} );
}

sub url_part {
    my ($url) = @_;
    return unless ($url);
    my $ourl = $url;
    return unless $url;
    $url =~ s#git\@(.*?):#https://$1/#;
    $url =~ s#^git.*\@#https://#;
    $url =~ s#.*git.*://#https://#;
    $url =~ s/\.git$//;
    $url =~ s/[\W]+$//;

    if ( $url =~ s#^(?:git\+)?(https?://)## ) {
        my $prot = $1;
        if ( $url =~ m#^([^/]+/[^/]+/[^/]+)# ) {
            return $prot . $1;
        }
    }
    die "Unable to parse $ourl";
}

sub git_last_version {
    my ($repo) = @_;
    return unless $repo;
    my $ua = LWP::UserAgent->new( timeout => 10 );
    $ua->env_proxy;
    my $response = $ua->get("$repo/tags");
    if ( $response->is_success ) {
        if ( $repo =~ /github/ ) {
            my @versions =
              sort {
                Dpkg::Version->new( "$a-0", check => 0 )
                  cmp Dpkg::Version->new( "$b-0", check => 0 )
              } ( $response->content =~ m#.*/archive.*/v?([\d\.]+).tar.gz#g );
            return @versions ? pop(@versions) : 0;
        }
    }
    else {
        return 0;
    }
}

sub git_watch {
    my ( $repo, $component, $type, $version, $after, $noctype, $dwatchVersion )
      = @_;
    $version = $version ? "v?($version(?:\.[\\d\\.]+)?)" : "v?([\\d\\.]+)";
    if ( $dwatchVersion && $dwatchVersion > 4 ) {
        $component = $component ? "Component: $component\n" : '';
        $type      = $type      ? "Version-Schema: $type\n" : '';
        $component .= "Ctype: nodejs\n" unless ($noctype);
    }
    else {
        $component = $component ? "component=$component,\\\n" : '';
        $type      = $type      ? " $type"                    : '';
        $component .= "ctype=nodejs,\\\n" unless ($noctype);
    }
    my $name = $repo;
    $name =~ s#.*/([^/]+)/?#$1#;
    $name ||= "to-be-fixed";

    if ( $repo =~ m#github.com/([^/]+)/([^/]+)# ) {
        my ( $own, $pj ) = ( $1, $2 );
        $after = $after ? "?after=$after" : '';
        unless ( $dwatchVersion and $dwatchVersion > 4 ) {
            return <<"EOF";
opts=\\
${component}dversionmangle=auto,\\
filenamemangle=s/.*?(\\d[\\d\\.-]*\@ARCHIVE_EXT\@)/node-$name-\$1/ \\
 $repo/tags$after .*/archive.*/$version.tar.gz$type
EOF
        }
        return <<"EOF";
${component}Template: Github
Owner: $own
Project: $pj

EOF
    }
    else {
        die "Unsupported repo $repo";
    }
}

sub registry_watch {
    my ( $pname, $component, $type, $version, $noctype, $dwatchVersion ) = @_;
    my $localName = $component ? "node-$component" : '@PACKAGE@';
    $version = $version ? "($version(?:\.[\\d\\.]+)?)" : "([\\d\\.]+)";
    if ( $dwatchVersion && $dwatchVersion > 4 ) {
        $component = $component ? "Component: $component\n" : '';
        $type      = $type      ? "Version-Schema: $type\n" : '';
        $component .= "Ctype: nodejs\n" unless ($noctype);
    }
    else {
        $component = $component ? ",component=$component" : '';
        $type      = $type      ? " $type"                : '';
        $component .= ",ctype=nodejs" unless ($noctype);
    }
    my $fname = $pname;
    $fname =~ s#.*/##;
    unless ( $dwatchVersion > 4 ) {
        return <<"EOF";
# It is not recommended use npmregistry. Please investigate more.
# Take a look at https://wiki.debian.org/debian/watch/
opts="searchmode=plain$component,pgpmode=none,filenamemangle=s/^.*?(\\d[\\d\\.-]*\@ARCHIVE_EXT\@)/$localName-\$1/" \\
 https://registry.npmjs.org/$pname https://registry.npmjs.org/$pname/-/$fname-$version\@ARCHIVE_EXT\@$type
EOF
    }
    return <<"EOF";
# It is not recommended use npmregistry. Please investigate more.
# Take a look at https://wiki.debian.org/debian/watch/
${component}${type}Search-Mode: plain
Pgp-Mode: node
Filename-Mangle: s/^.*?(\\d[\\d\\.-]*\@ARCHIVE_EXT\@)/$localName-\$1/
Source: https://registry.npmjs.org/$pname
Matching-Pattern: https://registry.npmjs.org/$pname/-/$fname-$version\@ARCHIVE_EXT\@$type
EOF
}
1;
