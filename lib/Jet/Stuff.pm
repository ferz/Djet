package Jet::Stuff;

use 5.010;
use Moose;
use MooseX::UndefTolerant;
use DBI;
use DBIx::TransactionManager 1.06;
use JSON;

use Jet::Stuff::Loader;
use Jet::Stuff::QueryBuilder;

with 'Jet::Role::Log';

=head1 NAME

Jet::Stuff

=head1 DESCRIPTION

How to save stuff in a Jet

=head1 SYNOPSIS

To be used internally by Jet

=head1 ATTRIBUTES

=head2 Parameters

=head3 dbname

The databasename

=head3 username

For database connectivity

=head3 password

For database connectivity

=head3 connect_options

For database connectivity

=cut

has 'dbname' => (isa => 'Str', is => 'ro');
has 'username' => (isa => 'Str', is => 'ro');
has 'password' => (isa => 'Str', is => 'ro');
has 'connect_options' => (isa => 'HashRef', is => 'ro');

=head2 Helper attributes

=head3 dbh

The actual database handle. You can provide one in the ->new call, or it will be created from the supplied parameters

=head3 txn_manager

The transaction manager

=head3 schema

The database schema

=head3 sql_builder

Helps you write sql

=head3 json

For (de)serializing data

=cut

has 'dbh' => (
	isa => 'DBI::db',
	is => 'ro',
	default => sub {
		my $self = shift;
		my $dsn = 'dbi:Pg:dbname='.$self->dbname;
		DBI->connect($dsn, $self->username, $self->password, $self->connect_options) or die;
	},
	lazy => 1,
);
has 'txn_manager' => (
	isa => 'DBIx::TransactionManager',
	is => 'ro',
	default => sub {
		my $self = shift;
		DBIx::TransactionManager->new($self->dbh);
	},
	lazy => 1,
);
has 'schema'       => (
	isa => 'DBIx::Inspector::Driver::Pg',
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		my $dbh = $self->dbh;
		my $loader = Jet::Stuff::Loader->new(dbh => $dbh);
		return $loader->schema;
	}
);
has 'sql_builder' => (
	isa => 'Jet::Stuff::QueryBuilder',
	is => 'ro',
	default => sub {
		Jet::Stuff::QueryBuilder->new();
	},
	lazy => 1,
);
has 'json' => (
	isa => 'JSON',
	is => 'ro',
	default => sub {
		JSON->new();
	},
	lazy => 1,
);

=head1 METHODS

=head2 Session type methods

=head3 disconnect

Disconnect from the database

=cut

sub disconnect {
	my $self = shift;
	delete $self->{txn_manager};
	if ( my $dbh = delete $self->{dbh} ) {
		$dbh->disconnect;
	}
}

=head2 Manipulating engines

=head3 insert_engine

Insert a Jet engine

=cut

sub insert_engine {
	my ($self, $data, $opt) = @_;
	$data->{recipe} = $self->json->encode($data->{recipe}) if $data->{recipe};
	my ($sql, @binds) = $self->sql_builder->insert(
		"jet.engine",
		$data,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
}

=head3 update_engine

Update Jet engine

=cut

sub update_engine {
	my ($self, $where, $args) = @_;
	my $sql = 'UPDATE jet.engine SET ' .
		join(',', map { "$_ = ?"} keys(%$args)) .
		' WHERE ' .
		join(',', map { "$_ = ?"} keys(%$where));
	$args->{recipe} = $self->json->encode($args->{recipe}) if $args->{recipe};
	my $sth = $self->_execute($sql, [ values %$args, values %$where ]) || return;
}

=head3 find_engine

Find a engine

=cut

sub find_engine {
	my ($self, $args) = @_;
	my $sql = 'SELECT * FROM jet.engine WHERE ' . join ',', map { "$_ = ?"} keys %$args;
	my $engine = $self->single(sql => $sql, data => [ values %$args ]) || return;
	$engine->{recipe} = $self->json->decode($engine->{recipe}) if $engine->{recipe};
	return $engine;
}

=head3 insert_or_update_engine

Insert or Update Jet engine

=cut

sub insert_or_update_engine {
	my ($self, $where, $args) = @_;
	my $engine = $self->find_engine($where);
	return $engine ?
		$self->update_engine($where, $args) :
		$self->insert_engine({%$where, %$args});
}

=head2 Manipulating basetypes

=head3 insert_basetype

Insert a Jet basetype

=cut

sub insert_basetype {
	my ($self, $data, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->insert(
		"jet.basetype",
		$data,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
}


=head3 update_basetype

Update Jet's basetype

=cut

sub update_basetype {
	my ($self, $where, $args) = @_;
	my $sql = 'UPDATE jet.basetype SET ' .
		join(',', map { "$_ = ?"} keys(%$args)) .
		' WHERE ' .
		join(',', map { "$_ = ?"} keys(%$where));
	my $sth = $self->_execute($sql, [ values %$args, values %$where ]) || return;
}

=head3 get_basetypes

Get all basetypes

=cut

sub get_basetypes {
	my ($self, $where, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->select(
		"jet.basetype",
		'*',
		$where,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
	return $sth->fetchall_arrayref({});
}

=head3 get_basetypes_href

Get all basetypes as hashref, id is key

=cut

sub get_basetypes_href {
	my ($self, $where, $opt) = @_;
	my $basetypes = $self->get_basetypes($where, $opt);
	return { map {
		$_->{recipe} = $self->json->decode($_->{recipe}) if $_->{recipe};
		$_->{role} = $self->_build_base_role($_);
		{ $_->{id} => $_ };
	} @$basetypes };
}

sub _build_base_role {
	my ($self, $basetype) = @_;
	my $role = Moose::Meta::Role->create_anon_role;
	my $colidx;
	for my $column (@{ $basetype->{columns} }) {
		$role->add_method( "get_$column", sub {my $self = shift;my $cols = $self->get_column('columns');return $cols->[$colidx++]} );
	}
	return $role;
}

=head3 find_basetype

Find a basetype

=cut

sub find_basetype {
	my ($self, $args) = @_;
	my $sql = 'SELECT * FROM jet.basetype WHERE ' . join ',', map { "$_ = ?"} keys %$args;
	my $basetype = $self->single(sql => $sql, data => [ values %$args ]) || return;
	$basetype->{recipe} = $self->json->decode($basetype->{recipe}) if $basetype->{recipe};
	return $basetype;
}

=head2 Manipulating nodes

=head3 find_node

Find a node

=cut

sub find_node {
	my ($self, $where, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->select(
		"jet.data_node",
		'*',
		$where,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
	return $sth->fetchrow_hashref;
}

=head3 search_node

Search in nodes

=cut

sub search_node {
	my ($self, $where, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->select(
		"jet.node",
		'*',
		$where,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
	return $sth->fetchall_arrayref({}),
}

=head3 ft_search_node

Fulltext search in nodes

=cut

sub ft_search_node {
    my ($self, $terms) = @_;
    my $ftsquery = join ' | ', split /\s+/, $terms;
    return $self->search_node(
		"fts @@ to_tsquery('english','$ftsquery')",
	);
}

=head3 insert

Insert a node

=cut

sub insert {
	my ($self, $data, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->insert(
		"jet.node",
		$data,
		$opt
	);
	return $self->single(sql => $sql, data => \@binds);
}

=head3 update

Update a node

=cut

sub update {
	my ($self, $data, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->update(
		"jet.node",
		$data,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
}

=head3 delete

Delete a node

=cut

sub delete {
	my ($self, $data, $opt) = @_;
	my ($sql, @binds) = $self->sql_builder->delete(
		"jet.node",
		$data,
		$opt
	);
	my $sth = $self->_execute($sql, \@binds);
}

=head3 move

Move a node to a new parent in the path tree

=cut

sub move {
	my ($self, $node_id, $parent_id) = @_;
	my $sql = qq{UPDATE
		jet.node
	SET
		parent_id=?
	WHERE
		node_id=?
	};
	return  $self->_execute($sql, [$parent_id, $node_id]);
}

=head3 execute

Prepare and execute

=cut

sub _execute {
	my ($self, $sql, $bind) = @_;
	my $sth = $self->dbh->prepare($sql);
	$sth->execute(@{$bind || []});
	return $sth;
}

=head3 single

Returns a single hashref from a query

=cut

sub single {
	my ($self, %args) = @_;
	my $sth = $self->_execute($args{sql}, $args{data});
	my $r = $sth->fetchrow_hashref();
	$sth->finish();
	return $r;
}

=head3 select_all

Returns all hashrefs from a query

=cut

sub select_all {
	my ($self, %args) = @_;
	my $sth = $self->dbh->prepare($args{sql}) || return 0;

	$self->set_bind_type($sth,$args{data} || []);
	unless($sth->execute(@{$args{data}})) {
		my @c = caller;
		print STDERR "File: $c[1] line $c[2]\n";
		print STDERR $args{sql}."\n" if($args{sql});
		return 0;
	}
	my @result;
	while( my $r = $sth->fetchrow_hashref) {
		push(@result,$r);
	}
	$sth->finish();
	return ( \@result );
}

=head2 Notification methods

=head3 listen

Starts listening to notifications

=cut

sub listen {
	my ($self, %args) = @_;
	my $queue = $args{queue} || return undef;

	for my $q (ref $queue ? @$queue : ($queue)) {
		$self->{dbh}->do(qq{listen "$q";});
	}
}

=head3 unlisten

Stops listening to notifications

=cut

sub unlisten {
	my ($self, %args) = @_;
	my $queue = $args{queue} || return undef;

	for my $q (ref $queue ? @$queue : ($queue)) {
		$self->{dbh}->do(qq{unlisten "$q";});
	}
}

=head3 notify

Send a notification

=cut

sub notify {
	my ($self, %args) = @_;
	my $queue = $args{queue} || return undef;
	my $payload = $args{payload};
	my $sql = qq{SELECT pg_notify(?,?)};
	my $task = $self->select_first(
		sql => $sql,
		data => [ $queue, $payload],
	);
}

=head3 get_notification

Get a notification

=cut

sub get_notification {
	my ($self,$timeout) = @_;
	my $dbh = $self->dbh;
	my $notifies = $dbh->func('pg_notifies');
	return $notifies;
}

=head3 set_listen

Start a blocking notification recieve loop

=cut

sub set_listen {
	my ($self,$timeout) = @_;
	my $dbh = $self->dbh;
	my $notifies = $dbh->func('pg_notifies');
	if (!$notifies) {
		my $fd = $dbh->{pg_socket};
		vec(my $rfds='',$fd,1) = 1;
		my $n = select($rfds, undef, undef, $timeout);
		$notifies = $dbh->func('pg_notifies');
	}
	return $notifies || [0,0];
}

# sub DESTROY {
	# $_[0]->disconnect();
	# return;
# }


=head2 Transaction management methods

=head3 in_transaction_check

=cut

sub in_transaction_check {
	my $self = shift;

	return unless $self->txn_manager;

	if ( my $info = $self->{txn_manager}->in_transaction ) {
		my $caller = $info->{caller};
		my $pid    = $info->{pid};
		Carp::confess("Detected transaction during a connect operation (last known transaction at $caller->[1] line $caller->[2], pid $pid). Refusing to proceed at");
	}
}

=head3 txn_scope

get DBIx::TransactionManager::ScopeGuard's instance object

=cut

sub txn_scope {
	my @caller = caller();
	$_[0]->txn_manager->txn_scope(caller => \@caller);
}

=head3 in_transaction

Checks if we're currently in a transaction

=head3 txn_begin

Start the transaction.

=head3 txn_rollback

Rollback the transaction.

=head3 txn_commit

Commit the transaction.

=head3 txn_end

=cut

sub in_transaction { $_[0]->txn_manager->in_transaction }
sub txn_begin      { $_[0]->txn_manager->txn_begin      }
sub txn_rollback   { $_[0]->txn_manager->txn_rollback   }
sub txn_commit     { $_[0]->txn_manager->txn_commit     }
sub txn_end        { $_[0]->txn_manager->txn_end        }

__PACKAGE__->meta->make_immutable;
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
