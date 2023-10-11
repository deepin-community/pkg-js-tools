package Debian::PkgJs::Cache;

use strict;
use Exporter 'import';
our @EXPORT=('&CACHEDELAY');

use constant CACHEDELAY => 86400;

sub new {
    my ( $class, %opts ) = @_;
    my $self = bless {}, $class;
    if ( $opts{clearcache} or !$opts{nocache} ) {
        require Cache::FileCache;
        $self->{_c} = new Cache::FileCache(
            {
                namespace          => 'PkgJsDepends',
                default_expires_in => $opts{cachedelay},
            }
        );
    }
    if ( $opts{clearcache} ) {
        $self->{_c}->Clear();
        exit 0;
    }
    elsif ( $self->{_c} ) {
        $self->{_c}->purge;
    }
    return $self;
}

sub get {
    my $self = shift;
    return $self->_cmd( 'get', @_ );
}

sub set {
    my $self = shift;
    return $self->_cmd( 'set', @_ );
}

sub _cmd {
    my $self = shift;
    my $cmd  = shift;
    return $self->{_c} ? $self->{_c}->$cmd(@_) : undef;
}

1;
