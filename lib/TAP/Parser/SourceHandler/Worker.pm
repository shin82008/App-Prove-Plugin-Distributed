package TAP::Parser::SourceHandler::Worker;

use strict;
use Getopt::Long;
use Sys::Hostname;
use IO::Socket::INET;
use IO::Select;

use vars (qw($VERSION @ISA));

use TAP::Parser::SourceHandler                ();
use TAP::Parser::IteratorFactory              ();
use TAP::Parser::Iterator::Worker             ();
use TAP::Parser::SourceHandler::Perl          ();
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

=head3 C<$use_local_public_ip>

Class static variable to flag the local public ip is needed.
Some of the home network might not have name server setup.  Therefore,
the public local ip is needed. 

=cut 

my $use_local_public_ip;

=head3 C<$local_public_ip>

Class static variable to store the local public ip is needed.
Some of the home network might not have name server setup.  Therefore,
the public local ip is needed. 

=cut 

my $local_public_ip;

=head3 C<can_handle>

  my $vote = $class->can_handle( $source );

Casts the following votes:
  
  Vote the same way as the L<TAP::Parser::SourceHandler::Perl> 
  but with 0.01 higher than perl source.
  
=cut

sub can_handle {
    my ( $class, $src ) = @_;
    my $vote = TAP::Parser::SourceHandler::Perl->can_handle($src);
    return 0 unless ($vote);
    if ( $src->{config} ) {
        my @config_keys = keys %{ $src->{config} };
        if ( scalar(@config_keys) == 1 ) {

            #LSF: If it is detach, we just run everythings.
            if ( $src->{config}->{ $config_keys[0] }->{detach} ) {
                $vote = 0.90;
            }
        }
    }

    #LSF: If it is a subclass, we will add 0.01 for each level of subclass.
    my $package = __PACKAGE__;
    my $tmp     = $class;
    $tmp =~ s/^$package//;
    my @number = split '::', $tmp;

    return $vote + ( 1 + scalar(@number) ) * 0.01;
}

=head1 SYNOPSIS

=cut

=head3 C<make_iterator>

  my $iterator = $class->make_iterator( $source );

Returns a new L<TAP::Parser::Iterator::Stream::Selectable> for the source.

=cut

sub make_iterator {
    my ( $class, $source, $retry ) = @_;

    my $worker = $class->get_a_worker($source);

    if ($worker) {
        $worker->autoflush(1);
        $worker->print( ${ $source->raw } . "\n" );
        return TAP::Parser::Iterator::Stream::Selectable->new(
            { handle => $worker } );
    }
    elsif ( !$retry ) {

        #LSF: Let check the worker.
        my @active_workers = $class->get_active_workers();

        #unless(@active_workers) {
        #   die "failed to find any worker.\n";
        #}
        @workers = @active_workers;

        #LSF: Retry one more time.
        return $class->make_iterator( $source, 1 );
    }

    #LSF: Pass through everything now.
    return;
}

=head3 C<get_a_worker>

  my $worker = $class->get_a_worker();

Returns a new workder L<IO::Socket>

=cut

sub get_a_worker {
    my $class   = shift;
    my $source  = shift;
    my $package = __PACKAGE__;
    my $tmp     = $class;
    $tmp =~ s/^$package//;
    my $option_name = 'Worker' . $tmp;
    $number_of_workers = $source->{config}->{$option_name}->{number_of_workers}
      || 1;
    my $startup   = $source->{config}->{$option_name}->{start_up};
    my $teardown  = $source->{config}->{$option_name}->{tear_down};
    my $error_log = $source->{config}->{$option_name}->{error_log};
    my $detach    = $source->{config}->{$option_name}->{detach};
    my %args      = ();
    $args{start_up}  = $startup             if ($startup);
    $args{tear_down} = $teardown            if ($teardown);
    $args{detach}    = $detach              if ($detach);
    $args{error_log} = $error_log           if ($error_log);
    $args{switches}  = $source->{switches};
    $args{test_args} = $source->{test_args} if ( $source->{test_args} );

    if ( @workers < $number_of_workers ) {
        my $listener = $class->listener;
        if ( $use_local_public_ip && !$local_public_ip ) {
            require Net::Address::IP::Local;
            $local_public_ip = Net::Address::IP::Local->public;
        }

        my $spec = (
            $local_public_ip
              || ( $listener->sockhost eq '0.0.0.0'
                ? hostname
                : $listener->sockhost )
          )
          . ':'
          . $listener->sockport;
        my $iterator_class = $class->iterator_class;
        eval "use $iterator_class;";
        $args{spec} = $spec;
        my $iterator = $class->iterator_class->new( \%args );
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
            Listen  => 5,
            Proto   => 'tcp',
            Timeout => 40,
        );
    }
    return $listener;
}

=head3 C<iterator_class>

The class of iterator to use, override if you're sub-classing.  Defaults
to L<TAP::Parser::Iterator::Worker>.

=cut

use constant iterator_class => 'TAP::Parser::Iterator::Worker';

=head3 C<workers>

Returns list of workers.

=cut

sub workers {
    return @workers;
}

=head3 C<get_active_workers>
  
  my @active_workers = $class->get_active_workers;

Returns list of active workers.

=cut

sub get_active_workers {
    my $class   = shift;
    my @workers = $class->workers;
    return unless (@workers);
    my @active;
    for my $worker (@workers) {
        next unless ( $worker && $worker->{sel} );
        my @handles = $worker->{sel}->can_read();
        for my $handle (@handles) {
            if ( $handle == $worker->{err} ) {
                my $error = '';
                if ( $handle->read( $error, 640000 ) ) {
                    chomp($error);
                    print STDERR "Worker with error [$error].\n";

                    #LSF: Close the handle.
                    $handle->close();
                    $worker = undef;
                    last;
                }
            }
        }
        push @active, $worker if ($worker);
    }
    return @active;
}

=head3 C<load_options>
  
Setup the worker specific options.

  my @active_workers = $class->load_options($app_prove_object, \@ARGV);

Returns boolean.

=cut

sub load_options {
    my $class = shift;
    my ( $app, $args ) = @_;
    {
        local @ARGV = @$args;
        Getopt::Long::Configure(qw(no_ignore_case bundling pass_through));

        # Don't add coderefs to GetOptions
        GetOptions( 'use-local-public-ip' => \$use_local_public_ip, )
          or croak('Unable to continue');

=cut
        # Example options setup.
        # Don't add coderefs to GetOptions
        GetOptions(
            'manager=s'          => \$app->{manager},
            'distributed-type=s' => \$app->{distributed_type},
            'start-up=s'         => \$app->{start_up},
            'tear-down=s'        => \$app->{tear_down},
            'error-log=s'        => \$app->{error_log},
            'detach'             => \$app->{detach},
        ) or croak('Unable to continue');

=cut

    }
    return 1;
}

1;

__END__

##############################################################################
