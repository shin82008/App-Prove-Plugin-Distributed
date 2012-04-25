package TAP::Parser::SourceHandler::Worker;

use strict;
use Sys::Hostname;
use IO::Socket::INET;
use IO::Select;

use vars (qw($VERSION @ISA));

use TAP::Parser::SourceHandler                ();
use TAP::Parser::Iterator::Worker             ();
use TAP::Parser::Iterator::Stream::Selectable ();
@ISA = 'TAP::Parser::SourceHandler';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);

=head1 NAME

TAP::Parser::SourceHandler::Worker - Stream TAP from an L<IO::Handle> or a GLOB.

=head1 VERSION

Version 0.01

=cut

$VERSION = '0.01';

=head3 C<@workers>

Class static variable to keep track of workers. 

=cut 

my @workers = ();

=head3 C<$number_of_workers>

Class static variable to keep track of number of workers. 

=cut 

my $number_of_workers;

=head3 C<$listener>

Class static variable to store the worker listener. 

=cut 

my $listener;

=head3 C<can_handle>

  my $vote = $class->can_handle( $source );

Casts the following votes:

  0.9 if $source is an IO::Handle
  0.8 if $source is a glob

=cut

sub can_handle {
    my ( $class, $src ) = @_;
    my $meta = $src->meta;

    #LSF: Do not handle the IO::Handle object.
    return 0
        if $meta->{is_object}
            && UNIVERSAL::isa( $src->raw, 'IO::Handle' );
    my $package = __PACKAGE__;
    my $tmp     = $class;
    $tmp =~ s/^$package//;
    my @number = split '::', $tmp;
    return '0.9' . scalar(@number);
}

=head1 SYNOPSIS

=cut

=head3 C<make_iterator>

  my $iterator = $class->make_iterator( $source );

Returns a new L<TAP::Parser::Iterator::Worker> for the source.

=cut

sub make_iterator {
    my ( $class, $source ) = @_;
    my $package = __PACKAGE__;
    my $tmp     = $class;
    $tmp =~ s/^$package//;
    my $option_name = 'Worker' . $tmp;
    $number_of_workers = $source->{config}->{$option_name}->{number_of_workers};

    my $worker = $class->get_a_worker;
    if ($worker) {
        $worker->print( ${ $source->raw } . "\n" );
        return TAP::Parser::Iterator::Stream::Selectable->new( { handle => $worker } );
    }

    #LSF: Pass through everything now.
    return;
}

=head3 C<get_a_worker>

  my $worker = $class->get_a_worker();

Returns a new workder L<IO::Socket>

=cut

sub get_a_worker {
    my $class = shift;
    if ( @workers < $number_of_workers ) {
        my $listener = $class->listener;
        my $spec = ( $listener->sockhost eq '0.0.0.0' ? hostname : $listener->sockhost ) . ':'
            . $listener->sockport;
        my $iterator_class = $class->iterator_class;
        eval "use $iterator_class;";
        my $iterator = $class->iterator_class->new( \$spec );
        push @workers, $iterator;
    }
    return $listener->accept();
}

=head3 C<listener>

  my $listener = $class->listener();

Returns worker listener L<IO::Socket::INET>

=cut

sub listener {
    my $class = shift;
    unless ($listener) {
        $listener = IO::Socket::INET->new(
            Listen => 5,
            Proto  => 'tcp'
        );
    }
    return $listener;
}

=head3 C<iterator_class>

The class of iterator to use, override if you're sub-classing.  Defaults
to L<TAP::Parser::Iterator::Worker>.

=cut

use constant iterator_class => 'TAP::Parser::Iterator::Worker';

sub workers {
    return @workers;
}

1;

__END__

##############################################################################
