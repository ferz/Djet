package Jet::Role::DB::Result::Node;

use 5.010;
use Moose::Role;
use namespace::autoclean;

=head1 NAME

Jet::Role::DB::Result::Node

=head1 DESCRIPTION

Common methods for nodes and datanodes.

=head1 METHODS

=head2 add

Add a new node

=cut

sub add {
	my ($self, $args) = @_;
	return unless ref $args eq 'HASH';
	for my $column (qw/title part/) {
		return unless defined $args->{$column};
	}

	my $opts = {returning => '*'};
	my $row = $self->schema->insert($self->basetype, $args, $opts);
	$self->_row($self->schema->row($row, $self->basetype));
}

=head2 move

Move node to a new parent

=cut

sub move {
	my ($self, $parent_id) = @_;
	return unless $parent_id and $self->row;

	my $opts = {returning => '*'};
	my $success = $self->schema->move($self->path_id, $parent_id);
}

=head2 add_child

Add a new child node to the current node

=cut

sub add_child {
	my ($self, $args) = @_;
	return unless ref $args eq 'HASH';

	$args->{parent_id} = $self->get_column('id');
	$args->{basetype_id} ||= $self->basetypes->{delete $args->{basetype}}{id} if $args->{basetype}; # Try to find basetype_id from basetype if that is defined
	for my $column (qw/basetype_id title/) {
		return unless ($args->{$column});
	}

	my $basetype = delete $args->{basetype};
	my $opts = {returning => '*'};
	return $self->new(
		row => $self->schema->insert($args, $opts),
	);
}

=head2 move_child

Move child node here

=cut

sub move_child {
	my ($self, $child_id) = @_;
	return unless $child_id and $self->row;

	my $opts = {returning => '*'};
	my $success = $self->schema->move($child_id, $self->get_column('id'));
}

=head2 children

Return the children of the current node

Extends the node method with a convenience search hashref

=cut

sub children {
	my ($self, %opt) = @_;
	return $self->nodes->search(\%opt);
}

=head2 parent

Return the parent of the current node

The parent, as found from the path

If the parent is on the stash, this node will be returned. Otherwise it will be looked up
in the database

=cut

sub parent {
	my ($self) = @_;
	my $stash = $self->stash;
	my $parent_id = $self->row->{parent_id};
	my $parent = $stash->{nodes}{$parent_id};
	return $parent if $parent;

	my $schema = $self->schema;
	my $where = {
		parent_id => $parent_id,
	};
	$parent = $schema->search($where);
	return Jet::Node->new(row => $parent, stash => $stash);
}

=head2 ancestors

Return the ancestors of the current node

Uses the parent method to utilize either the stash or the database

=cut

sub ancestors {
	my ($self) = @_;
	my $stash = $self->stash;

	my $node = $self;
	my @parents;
	while ($node->row->{parent_id}) {
		$node = $node->parent;
		push @parents, $node;
	}
	return [ reverse @parents ];
}

=head2 parents

Return the parents of the current node

A node can have several parents, and we know only one from the path, so this method always requires
a roundtrip to the database

Required parameters:

base_type

=cut

sub parents {
	my ($self, %opt) = @_;
	my $parent_base_type = $opt{base_type} || return;

	my $node_id = $self->get_column('id');
	my $where = {
		base_type => $self->basetype,
		node_id => $node_id,
	};
	my $nodes = $self->schema->search_nodepath(\%opt);
	my %nodes;
	for my $node (@$nodes) {
		push @{ $nodes{$node->{base_type}} }, $node;
	}
	my @result;
	my $schema = $self->schema;
	while (my ($base_type, $nodes) = each %nodes) {
		for my $node (@{ $nodes }) {
			$where = {
				id => $node->{node_id},
			};
			push @result, map {{%$node, %$_}} @{ $schema->search($base_type, $where) };
		}
	}
	return [ map {Jet::Node->new(row => $_)} @result ];
}

no Moose::Role;

1;

__END__

=head1 AUTHOR

Kaare Rasmussen, <kaare at cpan dot com>

=head1 BUGS 

Please report any bugs or feature requests to my email address listed above.

=head1 COPYRIGHT & LICENSE 

Copyright 2012 Kaare Rasmussen, all rights reserved.

This library is free software; you can redistribute it and/or modify it under the same terms as 
Perl itself, either Perl version 5.8.8 or, at your option, any later version of Perl 5 you may 
have available.
