package App::Prove::Plugin::Distributed;

use strict;
use Getopt::Long;
use Carp;
use Test::More;
use IO::Socket::INET;

=head1 NAME

App::Prove::Plugin::Distributed - to distribute test job using client and server model.

=head1 VERSION

Version 0.01

=cut

$VERSION = '0.01';

=head3 C<load>

Load the plugin configuration.
It will setup all of the tests to be distributed through the 
L<TAP::Parser::SourceHandler::Worker> source handler class.

=cut

sub load {
    my ( $class, $p ) = @_;
    my @args = @{ $p->{args} };
    my $app  = $p->{app_prove};

    {
        local @ARGV = @args;
        Getopt::Long::Configure(qw(no_ignore_case bundling pass_through));

        # Don't add coderefs to GetOptions
        GetOptions(
            'm|manager=s'          => \$app->{manager},
            't|distributed-type=s' => \$app->{distributed_type},
        ) or croak('Unable to continue');
    }

    if ( $app->{argv}->[0] =~ /--worker-option=number_of_workers=(\d+)/ ) {
        if ( $app->{jobs} ) {
            die
"-j and --worker-option=number_of_workers are mutually exclusive.\n";
        }
        else {
            $app->{jobs} = $1;
        }
    }
    elsif ( $app->{jobs} ) {
        unshift @{ $app->{argv} },
          '--worker-option=number_of_workers=' . $app->{jobs};
    }

    unless ( $app->{manager} ) {

        #LSF: Set the iterator.
        $app->sources(
            [
                'Worker'
                  . (
                    $app->{distributed_type}
                    ? '::' . $app->{distributed_type}
                    : ''
                  )
            ]
        );
        return 1;
    }

    while (1) {

        #LSF: The is the server to serve the test.
        $class->start_server( $app->{manager} );
    }
    return 1;
}

=head3 C<start_server>

Start a server to serve the test.

Parameter is the contoller peer address.

=cut

sub start_server {
    my $class = shift;
    my $spec  = shift;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $spec,
        Proto    => 'tcp'
    );
    unless ($socket) {
        die "failed to connect to controller with address : $spec.\n";
    }

    #LSF: Waiting for job from controller.
    my $job_info = <$socket>;
    chomp($job_info);

    #LSF: Run job.
    my $pid = fork();
    if ($pid) {
        waitpid( $pid, 0 );
    }
    elsif ( $pid == 0 ) {

        #LSF: Intercept all output from Test::More. Output all of them at one.
        my $builder = Test::More->builder;
        $builder->output($socket);
        $builder->failure_output($socket);
        $builder->todo_output($socket);
	#LSF: The code from here to exit is from  L<FCGI::Daemon> module.
        local *CORE::GLOBAL::exit = sub { die 'notr3a11yeXit' };
        local $0 = $job_info; #fixes FindBin (in English $0 means $PROGRAM_NAME)
        no strict;            # default for Perl5
        do $0;                # do $0; could be enough for strict scripts
        if ($EVAL_ERROR) {
            $EVAL_ERROR =~ s{\n+\z}{};
            print $socket "$0\n$EVAL_ERROR\n\b"
              unless $EVAL_ERROR =~ m{^notr3a11yeXit};
        }
        exit;
    }
    else {
        die "should not get here.\n";
    }
    $socket->close();
    return 1;
}

1;

__END__

##############################################################################
