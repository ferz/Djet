package Jet::Field;

use 5.010;
use Moose;
use namespace::autoclean;

use JSON;

with 'MooseX::Traits';

=head1 NAME

Jet::Field - Attributes and feature for Jet Fields

=head1 ATTRIBUTES

=head2 type

The field's type

=cut

has type => (
	is => 'ro',
	isa => 'Str',
	default => 'Text',
);

=head2 title

The field's title

=cut

has title => (
	is => 'ro',
	isa => 'Str',
);

=head2 value

The field's value

=cut

has value => (
	is => 'ro',
);

=head1 METHODS

=head2 as_json

Return the field (type, title, value) as JSON

=cut

sub as_json {
	my $self = shift;
	my $hash = { map {$_ => $self->$_} qw/type title value/ };
	return JSON->new->encode($hash);
}

no Moose::Role;

1;

# COPYRIGHT

__END__
