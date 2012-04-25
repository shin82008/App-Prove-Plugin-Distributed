package TAP::Parser::Iterator::Worker;

use strict;
use Sys::Hostname;
use IO::Socket::INET;
use IO::Select;

use TAP::Parser::Iterator::Process ();

use vars qw($VERSION @ISA);
@ISA = 'TAP::Parser::Iterator::Process';

=head1 NAME

TAP::Parser::Iterator::Worker - Iterator for worker TAP sources

=head1 VERSION

Version 0.01

=cut

$VERSION = '0.01';

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head3 C<new>

Make a new worker.

=cut

sub _initialize {
    my ( $self, $args ) = @_;
    $self->{spec} = $$args;   
    return unless($self->SUPER::_initialize({ command => [$self->initialize_worker_command->[0]]}));
    return $self;
}

=head3 C<initialize_worker_command>

Initialize the command to be used to initialize worker.

For your specific command, you can subclass this to put your command in this method.

=cut

sub initialize_worker_command {
    my $self = shift;
    if(@_) {
       $self->{initialize_worker_command} = shift;
    }
    unless($self->{initialize_worker_command}) {
        #LSF: Get hostname and port.
	my @args = ('-PDistributed="--manager=' . $self->{spec} . '"');
	#LSF: Find the library path.
	my $path;
	my $package = __PACKAGE__;
	$package =~ s/::/\//g;
	$package .= '.pm';
	if($INC{$package}) {
	   $path = $INC{$package};
	   $path =~ s/$package//;
	}
	$self->{initialize_worker_command} = ["perl -I $path /usr/local/bin/prove " . (join ' ',  @args, "")];
    }
    return $self->{initialize_worker_command};
}

1;

__END__

##############################################################################
