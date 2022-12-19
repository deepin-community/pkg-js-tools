package Debian::PkgJs::Npm;

use strict;
use warnings;
use JSON;
use LWP::UserAgent;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
  &pjson &npmdata &npmrepo
);

our $VERSION = '0.8.14';

my %json;
my %reg;

sub pjson {
    my ($dir) = @_;
    unless ( -e "$dir/package.json" ) {
        print STDERR "/!\\ $dir/package.json not found\n";
        return undef;
    }
    return $json{$dir} if $json{$dir};
    my $pkgjson;
    open $pkgjson, "$dir/package.json";
    my $content = join '', <$pkgjson>;
    close $pkgjson;
    eval { $json{$dir} = JSON::from_json($content) };
    if ($@) {
        print STDERR
          "npm registry returned malformed JSON:\n$content\n\nSkipping\n";
        return undef;
    }
    return $json{$dir};
}

sub npmdata {
    my ($name) = @_;
    return $reg{$name} if $reg{$name};
    my $ua = LWP::UserAgent->new( timeout => 10 );
    $ua->env_proxy;
    my $response = $ua->get("https://registry.npmjs.org/$name");
    if ( $response->is_success ) {
        my $reg;
        eval { $reg = JSON::from_json( $response->content ) };
        die "Malformed upstream registry: $@" if $@;
        return $reg{$name} = $reg;
    }
    else {
        print STDERR "Module $name unknown from npm registry\n";
        return undef;
    }
}

sub npmrepo {
    my ($name)   = @_;
    my $reg      = npmdata($name);
    my @versions = sort {
        Dpkg::Version->new( "$a-0", check => 0 )
          <=> Dpkg::Version->new( "$b-0", check => 0 )
    } keys %{ $reg->{versions} };
    my $latest = $reg->{'dist-tags'}->{latest};
    unless ($latest) {
        print STDERR "No latest version found in npm registry\n";
        return undef;
    }
    $reg = $reg->{versions}->{$latest}
      or die "Version $latest not found in npm registry";
    unless ( $reg->{repository} ) {
        unless ( $reg->{homepage} ) {
            print STDERR "No vcs repo found for $latest version\n";
            return ( $latest, undef );
        }
        return ( $latest, $reg->{homepage} );
    }
    $reg = $reg->{repository};
    if ( ref $reg ) {
        return ( $latest, $reg->{url}, \@versions );
    }
    else {
        return ( $latest, $reg, \@versions );
    }
}

1;
