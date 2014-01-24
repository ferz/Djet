package Jet::Role::Update;

use MooseX::MethodAttributes::Role;
use List::MoreUtils qw{ uniq };

=head1 NAME

Jet::Role::Update - generic methods for edit / create actions

=head1 DESCRIPTION

Handles edit functionality for Jet Engines

=head1 ATTRIBUTES

=head2 is_new

True if the node to be updated is new. False if not

Default false

=cut

has is_new => (
	is => 'rw',
	isa => 'Bool',
	lazy => 1,
	default => 0,
);

=head2 dont_render_edit

Set to true if the page isn't to be rendered

=cut

has dont_render_edit => (
	is => 'rw',
	isa => 'Bool',
);

=head1 METHODS

=head2 edit

Display object edit page.

=cut

sub edit {
	my ($self) = @_;

	my $request = $self->request->request;
	if ($request->parameters->{delete}) {
		$self->delete_submit;
		return;
	}

	if ($request->method eq 'POST') {
		if ($request->body_parameters->{save}) {
				$self->edit_submit;
		} else {
			my $response = $self->response;
			$response->redirect($response->uri_for($self->basenode->node_path));
		}
	}
	$self->_stash_defaults;
	$self->edit_view unless $self->dont_render_edit;
}

=head2 delete_submit

Delete the object in question.

=cut

sub delete_submit {
	my ($self) = @_;

	my $transaction=sub {
		$self->delete_node($self->basenode);
	};
	eval { $self->schema->txn_do($transaction) };
	my $error=$@;

	if ($error) {
		$self->config->log->debug($error);
		$self->stash->{message} = $error;
	} else {
		# XXX $self->flash->{notice}=$c->linkify("$display_name deleted.");
		$self->response->redirect($self->response->uri_for("/")); # XXX Where to redirect to? Might be parent ??
	}
}

=head2 delete_node

Delete the node inside a transaction

=cut

sub delete_node {
	my ($self, $node) = @_;
	$node->delete;
}

=head2 edit_submit

Controls the submit cycle

=cut

sub edit_submit {
	my ($self) = @_;
	my $validation = $self->edit_validation;

	if ($validation->success) {
		my $transaction = sub {
			if ($self->is_new) {
				my $node = $self->edit_create($validation);
				return unless ref $node; # local edit_create may choose not to create a new node

			} else {
				$self->edit_update($validation);
			}
		};

		my $error = $self->edit_submit_handle_transaction($transaction);
		if (!$error) {
			$self->edit_updated($validation) unless $self->dont_render_edit;
		} else {
			$self->edit_failed_update($validation, $error);
		}
	} else {
		$self->edit_failed_validation($validation);
	}
}

=head2 edit_submit_handle_transaction

The actual transaction.

=cut

sub edit_submit_handle_transaction {
	my ($self, $transaction) = @_;

	my $rs;
	eval {
		$rs = $self->schema->txn_do($transaction);
	};
	return $@;
}

=head2 edit_validation

Performs the validation with translation from fieldname to item->name

project and user components save the parameter in _text

=cut

sub edit_validation {
	my ($self) = @_;
	my $basetype = $self->basenode->basetype;
	my $validator = $basetype->validator;
	my $params = $self->request->request->body_parameters;
	return $validator->validate($params);
}

=head2 edit_failed_validation

Is called if the validation failed

=cut

sub edit_failed_validation {
	my ($self, $validation)=@_;
	my %msgs = %{ $validation->msgs };

	$self->stash->{msgs} //= {};
	@{ $self->stash->{msgs} }{ keys %msgs } = values %msgs;

	$self->logger->debug("Failed validation:\n\t" . join ("\n\t" , map {$_ . ' => ' . $msgs{$_}} keys %msgs)) if %msgs;
	my $node_type = $self->basenode->basetype->name;
	my $error = "Could not save $node_type information - see detailed information by positioning your mouse over the fields marked with orange background (same as this box) in the table below:";
	$self->logger->error($error);
	$self->stash->{message} ||= $error;
}

=head2 edit_update

Update the node. Called from within the transaction

=cut

sub edit_update {
	my ($self, $validation)=@_;

	my $node = $self->basenode;
	my $fields = $node->basetype->fields; 
	my @fieldnames = @{$fields->fieldnames};

	my $datacolumns;
	foreach my $fieldname (sort @fieldnames) {
		my $value = $validation->valid->{$fieldname};
		$datacolumns->{$fieldname} = $value
	}

	$node->update({datacolumns => $datacolumns});
	$node->discard_changes; # Necessary to keep db and dbic in sync
}

=head2 edit_create

Create the node from validation results. Called from within the transaction

Handling of not null constraints:
- Fields are updated before inserting the row in the DB
- edit_<field> methods are called before insertion the row if they appear in the edit_before_fields stash entry

Otherwise edit_<field> methods are called after inserting the row to make certain that the row exists. This is
necessary for methods that need a row to work on (e.g. in order to create related rows).

=cut

sub edit_create {
	my ($self, $validation)=@_;

	my $node = $self->basenode;
	my $fields = $node->basetype->fields; 
	my @fieldnames = @{$fields->fieldnames};

	my $datacolumns;
	foreach my $fieldname (sort @fieldnames) {
		my $value = $validation->valid->{$fieldname};
		$datacolumns->{$fieldname} = $value
	}
	my $new = $self->schema->resultset('DataNode')->create({
		# XXX Dummy values v
		basetype_id => 1,
		parent_id => 1,
		name => 'unnamed',
		title => 'no title',
		part => 'x',
		# XXX Dummy values ^
		datacolumns => $datacolumns
	});
	return $new;
}

=head2 edit_updated

Called if the update succeeds. Redirects to the new/changed node's path

The validation object is passed here in case any method modifier wants to use it.

=cut

sub edit_updated {
	my ($self, $validation)=@_;
	$self->response->redirect($self->response->uri_for($self->basenode->node_path));
}

=head2 edit_failed_update

Called if the update failed

=cut

sub edit_failed_update {
	my ($self, $validation, $error)=@_;
	die "Transaction AND Rollback failed!" if ($error =~ /Rollback failed/);

	$self->stash->{message} = $error;
	$self->log->debug($error);
	$self->stash->{title}='Could not update ' . $self->basenode->title;
}

=head2 edit_view

Show the edit page

=cut

sub edit_view {
	my ($self) = @_;
	$self->stash->{title} ||= $self->basenode->title;
}

sub _stash_defaults {
	my ($self) = @_;
	my $request = $self->request->request;
	$self->stash->{defaults} = $request->parameters;
	while (my ($fieldname, $upload) = each %{ $request->uploads }) {
		$self->stash->{defaults}{$fieldname} = $upload->filename;
	}
}

1;
