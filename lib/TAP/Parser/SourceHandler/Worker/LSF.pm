package TAP::Parser::SourceHandler::Worker::LSF;

use strict;
use vars (qw($VERSION @ISA));

use TAP::Parser::IteratorFactory ();
use TAP::Parser::SourceHandler::Worker ();
@ISA = 'TAP::Parser::SourceHandler::Worker';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);

=head1 NAME

TAP::Parser::SourceHandler::Worker::LSF - Stream TAP from an L<IO::Handle> or a GLOB.

=head1 VERSION

Version 0.01

=cut

$VERSION = '0.01';

use constant iterator_class => 'TAP::Parser::Iterator::Worker::LSF';

END {
    for my $worker ( __PACKAGE__->workers ) {
        my $command = 'bkill ' . $worker->{lsf_job_id};
        print join "\n", map { '#' . $_ } split /\n/, `$command`;
        print "\n";
    }
}

1;
