package Djet::Engine::ConfigTree;

use 5.010;
use Moose;

extends 'Djet::Engine::Default';

with qw/
	Djet::Part::Engine::Json
	Djet::Part::Treeview
/;

=head1 NAME

Djet::Engine::ConfigTree

=head1 DESCRIPTION

Djet::Engine::ConfigTree shows the node tree.

It includes the role L<Djet::Part::Treeview>.

=head1 ACCESSORS

__PACKAGE__->meta->make_immutable;

# COPYRIGHT

__END__
