package Djet::Engine::Admin::Config;

use 5.010;
use Moose;

extends 'Djet::Engine::Default';
with qw/
	Djet::Part::Log
	Djet::Part::Update::Node
/;

=head1 NAME

Djet::Engine::Admin::Config - Configure Djet

=head1 DESCRIPTION

Djet::Engine::Admin::Config configures Djet data and nodes.

It includes the role L<Djet::Part::Update::Node>.

=head1 ATTRIBUTES

=head1 METHODS

=head2 _build_validator

If it's a new node, we require some more attributes

=cut

before _build_validator => sub {
	my $self = shift;
	my $dfv = $self->dfv;
	return unless $self->is_new;

	push @{ $dfv->{required} }, qw/part parent_id basetype_id/;
	push @{ $dfv->{optional} }, qw/name title/;
	$self->set_dfv($dfv);
};

=head2 after set_base_object

Decide if we're creating a new node, and where in the process we are.

=cut

after 'set_base_object' => sub {
	my $self = shift;
	my $request = $self->request;
	return unless my $basetype_id = $request->parameters->{basetype_id};
	return $self->choose_basetype if $basetype_id eq 'child';

	my $parent_id = $self->rest_path;
	$self->set_object($self->schema->resultset('Djet::DataNode')->new({
		basetype_id => $basetype_id,
		parent_id => $parent_id,
		datacolumns => '{}',
	}));
	my $stash = $self->stash;
	$stash->{basetype_id} = $basetype_id;
	$stash->{parent_id} = $parent_id;
	$self->is_new(1);
};

=head2 before data

Control what to send when it's Djet config

=cut

before 'data' => sub {
	my $self = shift;
	my $object = $self->object;

	my $basecols = {
		columns => [
			{
				type => 'Str',
				title => 'Basetype',
				value => $object->basetype->name,
			},
			{
				type => 'Str',
				name => 'name',
				title => 'Name',
				value => $object->name,
				updatable => 1,
			},
			{
				type => 'Str',
				name => 'title',
				title => 'Title',
				value => $object->title,
				updatable => 1,
			},
			{
				type => 'Str',
				name => 'part',
				title => 'Part',
				value => $object->part,
				updatable => 1,
			},
		]
	};
	$self->stash->{basecols} = $basecols;
	$self->stash->{node} = $object;
};

=head2 before post_is_create

Decide if we're creating a new node

=cut

before 'post_is_create' => sub {
	my $self = shift;
	my $request = $self->body->request;
	$self->is_new(1) if $request->parameters->{parent_id} and $request->parameters->{basetype_id};
};

=head2 create_path

Redirect to the edit page of the new node.

=cut

sub create_path {
	my $self = shift;
	$self->response->redirect('/djet/node/' . $self->object->id);
}

=head2 choose_basetype

Put parameters on the stash for the choose_basetype template

=cut

sub choose_basetype {
	my ($self, $parent_path) = @_;
	my @basetypes = sort {$a->{id} <=> $b->{id}} map{{id => $_->id, title => $_->title}} values $self->schema->basetypes;
	$self->stash->{basetypes_choice} = \@basetypes;
	$self->template('/config/basenode_choose_basetype.tx');
}

__PACKAGE__->meta->make_immutable;

# COPYRIGHT

__END__
