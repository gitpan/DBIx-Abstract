package DBIx::Abstract;

use DBI;
use strict;
use vars qw( $AUTOLOAD $VERSION $LAST_CHANGE );

BEGIN {
  $DBIx::Abstract::VERSION = '0.91';
  q|
$Id: Abstract.pm,v 1.14 2000/03/31 22:38:54 turner Exp $
| =~ m/,v ([\d.]+) (\d+.\d+.\d+ \d+:\d+:\d+) /;
  $DBIx::Abstract::CVSVERSION = $1;
  $DBIx::Abstract::LAST_CHANGE = $2;
}

sub ___drivers {
  my($driver,$config) = @_;
  my %drivers = (
    # Feel free to add new drivers... note that some DBD data_sources
    # do not translate well (eg Oracle).
    mysql       => "dbi:mysql:$$config{dbname}:$$config{host}:$$config{port}",
    msql        => "dbi:msql:$$config{dbname}:$$config{host}:$$config{port}",
    # According to DBI, drivers should use the below if they have no
    # other preference.  It is ODBC style.
    DEFAULT     => "dbi:$driver:"
    );
  my @keys;
  foreach (keys(%$config)) {
    next if /^user$/;
    next if /^password$/;
    next if /^driver$/;
    push(@keys,"$_=$$config{$_}");
  }
  $drivers{'DEFAULT'} .= join(';',@keys);
  if ($drivers{$driver}) {
    return $drivers{$driver};
  } else {
    return $drivers{'DEFAULT'};
  }
}

sub new {
  my($class) = @_;
  warn "Calling the new method?  You probably didn't mean to...";
  return bless({},$class);
}

sub connect {
  my($class,$config,$options) = @_;
  my($dbh,$data_source,$user,$pass);
  my $self = {};
  
  if (ref($config) eq 'HASH') {
    $user = $$config{'user'} || $$config{'username'};
    $pass = $$config{'password'} || $$config{'pass'};
    if (!defined($$config{'user'}) && $$config{'password'}) {
      $$config{'password'} = undef;
    }
    if (exists($$config{'dsn'})) {
      $data_source = $$config{'dsn'};
    } else {
      $$config{'driver'} ||= 'mysql'; # Because it's what I use
      $$config{'dbname'} ||= $$config{'db'} || ''; 
      $$config{'host'} ||= '';
      $$config{'port'} ||= '';

      $data_source = ___drivers($$config{'driver'},$config);
    }
  } else {
    warn "DBIx::Abstract->connect Config should be hashref.  Using scalar is depricated.\n";
    $data_source = $config;
    $config = {};
  }

  if ($data_source) {
    $dbh = DBI->connect($data_source,$user,$pass);
  } else {
    die "Could not understand data source: $data_source\n";
  }

  if (!$dbh) { return 0 }
  bless $self, $class;
  $self->{'connect'} = {
    driver              => $$config{'driver'},
    dbname              => $$config{'dbname'},
    host                => $$config{'host'},
    port                => $$config{'port'},
    user                => $user,
    password            => $pass,
    data_source         => $data_source,
  };
  $self->{'dbh'} = $dbh;
  $self->opt(AutoCommit=>$self->{'dbh'}->{'AutoCommit'});
  $self->opt(loglevel=>0);
  foreach (keys(%$options)) {
    $self->opt($_,$$options{$_});
  }
  my @log;
  if (exists($$config{'dsn'})) {
    push(@log,'dsn=>'.$data_source) if defined($data_source);
  } else {
    foreach (qw( driver host port db )) {
      push(@log,$_.'=>'.$$config{$_}) if defined($$config{$_});
    }
  }
  push(@log,'user=>',$user) if defined($user);
  push(@log,'password=>',$pass) if defined($pass);
  $self->__logwrite(5,'Connect',@log);
  return $self;
}

sub ensure_connection {
  my($self) = @_;
  my $result = 0;
  my $connected = $self->connected;
  if ($self->connected) {
    ($result) = $self->select('1')->fetchrow_array;
    $self->disconnect unless $result;
  }
  unless ($result) {
    $result = $self->reconnect;
  }
  if ($result) {
    if ($result == 1) {
      $self->__logwrite(5,'ensure_connection','functioning');
    } elsif ($connected) {
      $self->__logwrite(5,'ensure_connection','failed; reestablished');
    } else {
      $self->__logwrite(5,'ensure_connection','reestablished');
    }
  } else {
    if ($connected) {
      $self->__logwrite(0,'ensure_connection','failed; could not reestablish');
    } else {
      $self->__logwrite(0,'ensure_connection','could not reestablish');
    }
    die "Could not ensure connection.\n";
  }
  return $self;
}

sub connected {
  my($self) = @_;
  my $connected = ($self->{'dbh'} and $self->{'dbh'}->{'Active'});
  $self->__logwrite(5,'connected',$connected);
  return $connected;
}

sub reconnect {
  my($self) = @_;
  my $dbh;
  if (!$self->connected and $self->{'connect'}{'data_source'}) {
    $dbh = DBI->connect(
      $self->{'connect'}{'data_source'},
      $self->{'connect'}{'user'},
      $self->{'connect'}{'password'});
  }
  if (!$dbh) {
    $self->__logwrite(5,'reconnect','fail');
    return 0;
  }
  $self->__logwrite(5,'reconnect','success');
  $self->{'dbh'} = $dbh;
  $self->opt('AutoCommit',$self->{'dbh'}->{'AutoCommit'});

  my @tolog;
  foreach (qw( host port dbname user password )) {
    push(@tolog, $self->{'connect'}{$_}) if $self->{'connect'}{$_};
  }
  $self->__logwrite(5,'Reconnect',@tolog);
  return $self;
}

sub DESTROY {
  my $self = shift;
  $self->finish if $self->{'sth'};
  if (!$self->{'ORIG'}) {
    if ($self->{'CLONES'}) {
      foreach (@{$self->{'CLONES'}}) {
        $_->DESTROY if ref($_);
        $_=undef;
      }
    }
    $self->disconnect;
  } else {
    my $new;
    foreach (@{$self->{'ORIG'}->{'CLONES'}}) {
      push(@$new,$_) if ($self ne $_);
    }
    $self->{'ORIG'}->{'CLONES'} = $new;
  }
  $self->{'sth'}->finish if $self->{'sth'};
  $self->{'dbh'} = undef;
  $self->{'sth'} = undef;
#  $self->{'connect'} = undef;
  $self->{'options'} = undef;
  $self->{'MODQUERY'} = undef;
  $self->{'ORIG'} = undef;
  $self->{'CLONES'} = undef;
}

sub clone {
  my $self = shift;
  my $class = ref($self);
  my $newself = {};
  bless $newself, $class;
  %$newself = %$self;
  if (!$self->{'ORIG'}) {
    $newself->{'ORIG'} = $self;
  }
  push(@{$newself->{'CLONES'}},$newself);
  $self->__logwrite(5,'Cloned');
  return $newself;
}


sub opt {
  my($self,$key,$value) = @_;
  if (ref($key)) {
    $value = $$key{'value'};
    $key = $$key{'key'};
  }
  my $ret = $self->{'options'}{$key};
  if (defined($value)) {
    if ($key eq 'AutoCommit') {
      eval { $self->{'dbh'}->{'AutoCommit'} = $value };
      if ($@) {
        warn $@;
        return $ret;
      }
    }
    $self->{'options'}{$key} = $value;
    $self->__logwrite(5,'Option change',$key?$key:'',$ret?$ret:'',$value?$value:'');
  }
  return $ret;
}

sub __literal_query {
  # This actually makes a query
  # All of the other related query functions (eventually) call this
  my($self,$sql,@bind_values)= @_;
  my $sth;
  if ($self->opt('saveSQL')) {
    my @bind_copy = @bind_values;
    $self->{'lastsql'} = $sql;
    $self->{'lastsql'} =~ s/\?/$self->quote(shift(@bind_copy))/eg;
  }
  if ($self->opt('useCached')) {
    $sth=$self->{'dbh'}->prepare_cached($sql); 
  } else {             
    $sth=$self->{'dbh'}->prepare($sql);
  }
  if (!$sth) {
    eval('use Carp;');
    die 'DBIx::Abstract (prepare): '.$self->{'dbh'}->errstr."\n".
        "    SQL: $sql\n".
        "STACK TRACE\n".
        Carp::longmess()."\n";
  }
  if (!$sth->execute(@bind_values)) {
    eval('use Carp;');
    die 'DBIx::Abstract (execute): '.$sth->errstr."\n".
        "    SQL: $sql\n".
        "STOCK TRACE\n".
        Carp::longmess()."\n";
  }
  $self->{'sth'} = $sth;
  return $self;
}

sub __mod_query {
  # This is used by queries that make changes.
  # This way we can process these tasks later if we want to.
  my($self,$sql,@bind_params) = @_;
  if ($self->opt('delaymods')) {
    if ($self->{'ORIG'}) { $self = $self->{'ORIG'} }
    push(@{$self->{'MODQUERY'}},[$sql,@bind_params]);
  } else {
    $self->__literal_query($sql,@bind_params);
  }
  return $self;
}

sub query {
  my($self,$sql,@bind_params) = @_;
  if (ref($sql) eq 'HASH') {
    @bind_params = @{$$sql{'bind_params'}};
    $sql = $$sql{'sql'};
  }
  $self->__logwrite_sql(3,$sql,@bind_params);
  return $self->__literal_query($sql,@bind_params);
}

sub __logwrite {
  # This writes to the log file if the loglevel is greater then 0
  # and the logfile has been set.
  # LOGLEVEL: 0 -- Fatal errors only
  # LOGLEVEL: 1 -- Modifications
  # LOGLEVEL: 2 -- And selects
  # LOGLEVEL: 3 -- And user created queries
  # LOGLEVEL: 4 -- And results of queries
  # LOGLEVEL: 5 -- And other misc commands
  # LOGLEVEL: 6 -- Internals of commands
  my($self,$level,@log) = @_;
  $level = 5 if $level+0 ne $level;
  if ($#log==-1) { @log = ('Something happened') }
  # Write a line to the log file
  if ($self->opt('logfile') && $self->opt('loglevel')>=$level) {
    local *LOG;
    if (open(LOG,'>>'.$self->opt('logfile'))) {
      print LOG join(chr(9),scalar(localtime()),$level,@log),"\n";
      close(LOG);
    }
  }
  return $self;
}

sub __logwrite_sql {
  my($self,$level,$sql,@bind) = @_;
  $level ||= 5;
  if (!defined($sql)) {
    $sql = 'Something happened, and I thought it was SQL';
  }
  # Write a line to the log file
  if ($self->opt('logfile') && $self->opt('loglevel')>=$level) {
    local *LOG;
    if (open(LOG,'>>'.$self->opt('logfile'))) {
      my $logsql = $sql;
      my @bind_copy = @bind;
      $logsql =~ s/\?/$self->quote(shift(@bind_copy))/eg;
      unshift(@bind_copy,'EXTRA BOUND PARAMS: ') if @bind_copy;
      print LOG join(chr(9),scalar(localtime()),$level,$logsql,@bind_copy),"\n";
      close(LOG);
    }
  }
  return $self;
}

sub run_delayed {
  my($self) = @_;
  if ($self->{'ORIG'}) { $self = $self->{'ORIG'} }
  $self->__logwrite(5,'Run delayed');
  foreach (@{$self->{'MODQUERY'}}) {
    $self->__literal_query(@$_);
  }
  return $self;
}

sub __where {
  my($self,$where,$int) = @_;
  # $where == This is either a scalar, hash-ref or array-ref
  #           If it is a scalar, then it is used as the literal where.
  #           If it is a hash-ref then the key is the field to check,
  #           the value is either a literal value to compare equality to,
  #           or an array-ref to an array of operator and value.
  #             {first=>'joe',age=>['>',26],last=>['like',q|b'%|]}
  #           Would produce:
  #             WHERE first=? AND age > ? AND last is like ?
  #             and add joe, 26 and b'% to the bind_params list
  #           If it is an array-ref then it is an array of hash-refs and
  #           connectors:
  #             [{first=>'joe',age=>['>',26]},'OR',{last=>['like',q|b'%|]}]
  #           Would produce:
  #             WHERE (first=? AND age > ?) OR (last like ?)
  #             and add joe, 26 and b'% to the bind_params list
  my $result='';
  my @bind_params;
  $int ||= 0;

  if ($int > 20) {
    $self->__logwrite(0,'Where parser iterated too deep (limit of 20)');
    die "DBIx::Abstract Where parser iterated too deep, circular reference in where clause?\n";
  }

  $self->__logwrite(6,'Where called with: ',$where);

  if (ref($where) eq 'ARRAY') {
    $self->__logwrite(7,'Where is array...');
    foreach (@$where) {
      if (ref($_) eq 'HASH') {
        $self->__logwrite(7,'Found where component of type hash');
        my($moreres,@morebind) = $self->__where_hash($_);
        $result .= "($moreres)" if $moreres;
        push(@bind_params,@morebind);
      } elsif (ref($_) eq 'ARRAY') {
        $self->__logwrite(7,'Found where component of type array');
        my($moreres,@morebind) = $self->__where($_,$int+1);
        $result .= "($moreres)" if $moreres;
        push(@bind_params,@morebind);
      } else {
        $self->__logwrite(7,'Found where component of type literal: '.$_);
        $result .= " $_ ";
      }
    }
  } elsif (ref($where) eq 'HASH') {
    $self->__logwrite(7,'Where is hash...');
    my($moreres,@morebind) = $self->__where_hash($where);
    $result = $moreres;
    @bind_params = @morebind;
  } else {
    $self->__logwrite(7,'Where is literal...');
    $result = $where;
  }
  $self->__logwrite(6,$int?0:1,'Where returning with: ',$result);
  if ($result) {
    return ($int?'':' WHERE ').$result,@bind_params;
  } else {
    return '';
  }
}

sub __where_hash {
  my($self,$where) = @_;
  my $ret;
  my @bind_params;
  $self->__logwrite(7,'Processing hash');
  foreach (keys(%$where)) {
    $self->__logwrite(7,'key',$_,'value',$$where{$_});
    if ($ret) { $ret .= ' AND ' }
    $ret .= "$_ ";
    if (ref($$where{$_}) eq 'ARRAY') {
      $self->__logwrite(7,'Value is array',@{$$where{$_}});
      $ret .= $$where{$_}[0].' ?';
      push(@bind_params,$$where{$_}[1]);
    } else {
      $self->__logwrite(7,'Value is literal',$$where{$_});
      if (defined($$where{$_})) {
        $ret .= '= ?';
        push(@bind_params,$$where{$_});
      } else {
        $ret .= 'IS NULL';
      }
    }
  }
  if ($ret ne '()') {
    return $ret,@bind_params;
  } else {
    return '';
  }
}

sub delete {
  my($self,$table,$where) = @_;
  # $table == Name of table to update
  # $where == One of my handy-dandy standard where's.  See __where.
  my($sql,@keys,$i);
  if (ref($table)) {
    $where = $$table{'where'};
    $table = $$table{'table'};
  }

  $table or die 'DBIx::Abstract: delete must have table';

  my($res,@bind_params) = $self->__where($where);
  $sql = "DELETE FROM $table".$res;
  $self->__logwrite_sql(1,$sql,@bind_params);
  $self->__mod_query($sql,@bind_params);
  return $self;
}

sub insert {
  my($self,$table,$fields)=@_;
  # $table  == Name of table to update
  # $fields == A reference to a hash of field/value pairs containing the
  #            new values for those fields.
  my($sql,@keys,@values,$i);
  my(@bind_params);
  if (ref($table)) {
    $fields = $$table{'fields'};
    $table = $$table{'table'};
  }

  $table or die 'DBIx::Abstract: insert must have table';

  $sql = "INSERT INTO $table ";
  if (ref($fields) eq 'HASH') {
    @keys = keys(%$fields); @values = values(%$fields);
    $#keys>-1 or die 'DBIx::Abstract: insert must have fields';
    $sql .= '(';
    for ($i=0;$i<=$#keys;$i++) {
      if ($i) { $sql .= ',' }
      $sql .= ' '.$keys[$i];
    }
    $sql .= ') VALUES (';
    for ($i=0;$i<=$#keys;$i++) {
      if ($i) { $sql .= ', ' }
      $sql .= '?';
      push(@bind_params,$values[$i]);
    }
    $sql .= ')';
  } elsif (!ref($fields) and $fields) {
    $sql .= $fields;
  } else {
    die 'DBIx::Abstract: insert must have fields';
  }
  $self->__logwrite_sql(1,$sql,@bind_params);
  $self->__mod_query($sql,@bind_params);
  return $self;
}

sub replace {
  my($self,$table,$fields)=@_;
  # $table  == Name of table to update
  # $fields == A reference to a hash of field/value pairs containing the
  #            new values for those fields.
  my($sql,@keys,@values,$i);
  my(@bind_params);
  if (ref($table)) {
    $fields = $$table{'fields'};
    $table = $$table{'table'};
  }

  $table or die 'DBIx::Abstract: replace must have table';

  $sql = "REPLACE INTO $table ";
  if (ref($fields) eq 'HASH') {
    @keys = keys(%$fields); @values = values(%$fields);
    $#keys>-1 or die 'DBIx::Abstract: replace must have fields';
    $sql .= '(';
    for ($i=0;$i<=$#keys;$i++) {
      if ($i) { $sql .= ',' }
      $sql .= ' '.$keys[$i];
    }
    $sql .= ') VALUES (';
    for ($i=0;$i<=$#keys;$i++) {
      if ($i) { $sql .= ', ' }
      $sql .= '?';
      push(@bind_params,$values[$i]);
    }
    $sql .= ')';
  } elsif (!ref($fields) and $fields) {
    $sql .= $fields;
  } else {
    die 'DBIx::Abstract: replace must have fields';
  }
  $self->__logwrite_sql(1,$sql,@bind_params);
  $self->__mod_query($sql,@bind_params);
  return $self;
}

sub update {
  my($self,$table,$fields,$where) = @_;
  # $table   == Name of table to update
  # $fields  == A reference to a hash of field/value pairs containing the
  #             new values for those fields.
  # $where == One of my handy-dandy standard where's.  See __where.
  my($sql,@keys,@values,$i);
  my(@bind_params);
  if (ref($table)) {
    $where = $$table{'where'};
    $fields = $$table{'fields'};
    $table = $$table{'table'};
  }

  # "If you don't know what to do, don't do anything."
  #          -- St. O'Ffender, _Return of the Roller Blade Seven_
  $table or die 'DBIx::Abstract: update must have table';

  $sql = "UPDATE $table SET";
  if (ref($fields) eq 'HASH') {
    @keys = keys(%$fields);
    @values = values(%$fields);
    $#keys>-1 or die 'DBIx::Abstract: update must have fields';
    for ($i=0;$i<=$#keys;$i++) {
      if ($i) { $sql .= ',' }
      $sql .= ' '.$keys[$i].'=?';
      push(@bind_params,$values[$i]);
    }
  } elsif (!ref($fields) and $fields) {
    $sql .= " $fields";
  } else {
    die 'DBIx::Abstract: update must have fields';
  }

  my($moresql,@morebind) = $self->__where($where);
  $sql .= $moresql;
  push(@bind_params,@morebind);

  $self->__logwrite_sql(1,$sql,@bind_params);
  $self->__mod_query($sql,@bind_params);
  return $self;
}

sub select {
  my $self = shift;
  my($fields,$table,$where,$order,$extra) = @_;
  # $fields  == A hash ref with the following values
  #   OR
  # $fields  == Fields to get data on, usually a *. (either scalar or
  #             array ref)
  # $table   == Name of table to update
  # $where   == One of my handy-dandy standard where's.  See __where.
  # $order   == The order to output in
  my $group;#== The key to group by, only available in hash mode
  my($sql,@keys,$i,$join);
  if (ref($fields) eq 'HASH') {
    my $field;
    foreach (keys(%$fields)) {
      my $field = $_;
      $field = lc($field);
      if (/^-(.*)/) { $field = $1 }
      $$fields{$field} = $$fields{$_};
    }
    $table = $$fields{'table'} || $$fields{'tables'};
    $where = $$fields{'where'};
    $order = $$fields{'order'};
    $group = $$fields{'group'};
    $extra = $$fields{'extra'};
    $join  = $$fields{'join'};

    $fields = $$fields{'fields'} || $$fields{'field'};
  }
  $sql = 'SELECT ';
  if (ref($fields) eq 'ARRAY') {
    $sql .= join(',',@$fields);
  } else {
    $sql .= $fields;
  }
  if (ref($table) eq 'ARRAY') {
    if ($#$table>-1) {
      $sql.=' FROM '.join(',',@$table);
    }
  } else {
      $sql.=" FROM $table" if $table;
  }

  my($addsql,@bind_params);
  if (defined($where)) {
    ($addsql) = $self->__where($where,1);
    unless ($addsql) {
      $where = undef;
    }
  }

  if ($join) {
    unless (ref($join)) {
      $join = [$join];
    }
    if ($where) {
      $where = [$where];
    } else {
      $where = [];
    }
    foreach (@{$join}) {
      push(@$where,'and') if $#$where>-1;
      push(@$where, [$_]);
    }
  }

  if (defined($where)) {
    ($addsql,@bind_params) = $self->__where($where);
    $sql .= $addsql;
  }

  if (ref($group) eq 'ARRAY') {
    if ($#$group>-1) {
      $sql .= ' GROUP BY '.join(',',@$group);
    }
  } elsif ($group) {
    $sql .= " GROUP BY $group";
  }

  if (ref($order) eq 'ARRAY') {
    if ($#$order>-1) {
      $sql .= ' ORDER BY '.join(',',@$order);
    }
  } elsif ($order) {
    $sql .= " ORDER BY $order";
  }

  if ($extra) {
    $sql .= ' '.$extra;
  }

  $self->__logwrite_sql(2,$sql,@bind_params);
  $self->__literal_query($sql,@bind_params);
  return $self;
}

sub select_one_to_hashref {
  my $self = shift;
  # Run a select and return a hash-ref of the first
  # record returned from the select.  Don't step
  # on the current query, and don't keep the new
  # one around.
  my $db = $self->clone;
  $self->__logwrite(2,'select_one_to_hash');
  $db->select(@_);
  my $result = $db->fetchrow_hashref;
  $db = undef;
  return {%$result};
}

sub select_all_to_hashref {
  my $self = shift;
  # Run a select and return a hash-ref.
  # The hash-ref's key is the first
  # field and it's value is the second.
  # And it won't step on a current query.
  my $db = $self->clone;
  $self->__logwrite(2,'select_all_to_hash');
  $db->select(@_);
  my $result = $db->fetchall_arrayref;
  my %to_ret;
  foreach (@$result) {
    if ($#$_>1) {
      my $key = shift(@$_);
      $to_ret{$key} = [@$_];
    } else {
      $to_ret{$$_[0]} = $$_[1];
    }
  }
  $db = undef;
  return {%to_ret};
}

sub fetchrow_hashref {
  my($self) = @_;
  $self->__logwrite(4,'fetchrow_hashref');
  return $self->{'sth'}->fetchrow_hashref;
}

sub fetchrow_hash {
  my($self) = @_;
  my $result = $self->fetchrow_hashref;
  $self->__logwrite(4,'fetchrow_hash');
  if ($result) {
    return %$result;
  } else {
    return ();
  }
}

sub fetchrow_arrayref {
  my($self) = @_;
  $self->__logwrite(4,'fetchrow_arrayref');
  return $self->{'sth'}->fetchrow_arrayref;
}

sub fetchrow_array {
  my($self) = @_;
  $self->__logwrite(4,'fetchrow_array');
  return $self->{'sth'}->fetchrow_array;
}

sub fetchall_arrayref {
  my($self) = @_;
  $self->__logwrite(4,'fetchall_arrayref');
  return $self->{'sth'}->fetchall_arrayref;
}

sub dataseek {
  my($self, $pos) = @_;
  if (ref($pos)) {
    $pos = $$pos{'pos'};
  }
  if ($self->{'connect'}{'driver'} eq 'mysql' or 
      $self->{'connect'}{'driver'} eq 'msql') {
    return $self->func($pos, 'dataseek');
  } else {
    die 'Dataseek is not supported by your database '.$self->{'connect'}{'driver'};
  }
}

sub rows {
  my($self) = @_;
  $self->__logwrite(5,'rows');
  return $self->{'sth'}->rows;
}

sub errstr {
  my($class) = @_;
  my $self;
  if (ref($class)) { $self = $class }
  if ($self and $self->{'dbh'}) {
    return $self->{'dbh'}->errstr;
  } else {
    return $DBI::errstr;
  }
}

sub err {
  my($class) = @_;
  my $self;
  if (ref($class)) { $self = $class }
  if ($self and $self->{'dbh'}) {
    return $self->{'dbh'}->err;
  } else {
    return $DBI::err;
  }
}

#### Mysql compatibility functions
#### These are not documented, and shouldn't be.
#### They are here to make it easier for lazy people
#### to switch.
#### These may get warnings associated with them.
#### These may go away.

sub fetchrow {
  my($self) = shift;
  return $self->fetchrow_array(@_);
}

sub fetchhash {
  my($self) = shift;
  return $self->fetchrow_hash(@_);
}

sub numrows {
  my($self) = shift;
  return $self->rows(@_);
}

sub quote {
  my($self) = shift;
  $self->{'dbh'}->quote(@_);
}

sub AUTOLOAD {
  ### This will delegate calls for selected methods from the DBH and STH
  ### objects.  This allows users limited access to their functionality.
  my($self) = shift;
  # $self == 'Class=REFERENCE'
  my($class) = split(/=/,$self);
  # $AUTOLOAD == 'Class::method'
  my $method = $AUTOLOAD; my $sr = '^'.$class.'::'; $method =~ s/$sr//;
  
  # These are just space separated lists of methods that may be passed
  # through to the dbh or sth objects respectively.
  #
  # If anything ends up in here we should probably make a seperate function
  # for it (if only to keep the logging working properly).
  my $DBHVALIDMETHODS = 
       'disconnect '.
       'commit '.
       'rollback '.
       'trace';
  my $STHVALIDMETHODS =
       'finish '.
       'bind_col '.
       'bind_columns';
       
  # If this is a dbh method, pass it through
  if ($DBHVALIDMETHODS =~ /\b$method\b/) {
    $self->__logwrite(5,"dbh->$method");
    return $self->{'dbh'}->$method(@_) if $self->{'dbh'};
  # If this is an sth method, pass it through
  } elsif ($STHVALIDMETHODS =~ /\b$method\b/) {
    $self->__logwrite(5,"sth->$method");
    return $self->{'sth'}->$method(@_) if $self->{'sth'};
  } else {
    $self->__logwrite(0,"Unknown method: class=$class method=$method");
    die "($$)Unknown method: class=$class method=$method\n";
  }
}

1;
__END__

=pod

=head1 NAME

DBIx::Abstract - DBI SQL abstraction

=head1 SYNOPSIS

  use DBIx::Abstract;
  $db = DBIx::Abstract->connect({
    driver=>'mydriver',
    host=>'myhost.org',
    dbname=>'mydb',
    user=>'myuser',
    password=>'mypassword',
    });

  if ($db->select('*','table')->rows) {
    while ($data = $db->fetchrow_hashref) {
      ...
    }
  }

  ($name) = $db->select('name','table',{id=>$id})->fetchrow_array;

  ***
  
  $db = DBIx::Abstract->connect( { driver=>'csv', f_name=>'foo/' } );
  
  ***
  
  $db = DBIx::Abstract->connect({
    dsn=>'dbi:someotherdb:so_db_name=mydb',
    user=>'myuser',
    password=>'mypassword',
    });

=head1 DESCRIPTION

This module provides methods for doing manipulating database tables This
module provides methods retreiving and storing data in SQL databases.
It provides methods for all of the more important SQL commands (like
SELECT, INSERT, REPLACE, UPDATE, DELETE).

It endeavors to produce an interface that will be intuitive to those already
familiar with SQL.

Notable features include:

  * data_source generation for some DBD drivers.
  * Can check to make sure the connection is not stale and reconnect
    if it is.
  * Controls statement handles for you.
  * Can delay writes.
  * Generates complex where clauses from hashes and arrays.
  * Shortcuts (convenience functions) for some common cases. (Like
    select_all_to_hashref.)

=head1 METHODS

Unless otherwise mentioned all methods return the database handle.

=over 5

=head2 connect

C<connect($connect_config[,$options])> I<CONSTRUCTOR>

Open a connection to a database as configured by $connect_config.
$connect_config can either be a scalar, in which case it is a DBI data
source, or a reference to a hash with the following keys:

 dsn      -- The data source to connect to your database
 
 OR, DBIx::Abstract will try to generate it if you give these instead:

 driver   -- DBD driver to use (defaults to mysql)
 host     -- Host of database server
 port     -- Port of database server
 dbname   -- Name of database

 Username and password are always valid.

 user     -- Username to connect as
 password -- Password for user

Options is a hash reference.  Each key/value pair is passed on to the opt
method.

=head2 clone

This clones the object.  For those times when you need a second
connection to the same DB.  If you need a second connection to a
different DB, create a new object with 'connect'.

This operation is logged at level 5 with the message "Cloned."

=head2 connected

Check to see if this object is connected to a database.  It checks to see if
it has a database handle and if that handle's "Active" attribute is true.

=head2 reconnect

If the object is not connected to a database it will reconnect using the
same parameters connect was originally called with.

=head2 ensure_connection

Makes sure that the object is connect to a database.  Makes sure that the
connect is active (by sending a "SELECT 1").  If there is no connection, or
the connection is not active then it tries to reconnect.  If it fails to
reconnect then it dies.

=head2 opt

($key[,$value])

({key=>$key[,value=>$value])

Set option $key to $value.  Available keys are:

  loglevel (default 0)
      0 -- Fatal errors only
      1 -- Modifications
      2 -- And selects
      3 -- And user created queries
      4 -- And results of queries
      5 -- And other misc commands
      6 -- Internals of commands

  logfile (default undef)
    Log file

  delaymods (default false)
    Delay making modifications to the database until
    run_delayed is run.
    
  AutoCommit
    This works just like the DBI 'AutoCommit', except that it issues a
    warning (instead of dieing) if you give it bad data.
    
  useCached
    If this is true then prepare_cached is used instead of prepare.
    Checkout the DBI documentation on this feature before using this
    feature.

  saveSQL
    If this is true then with each query DBIx::Abstract will stuff the generated
    SQL into the 'lastsql' key in the self payload.

This operation is logged at level 5 with the message "Option Change" and the
the key, the old value and new new value.

=head2 query

($sql,@bind_params)

({sql=>$sql,bind_params=>[@bind_params]})

This sends $sql to the database object's query method.  This should be used
for applications where the existing methods are not able to generate
flexible enough SQL for you.

If you find yourself using this very often with things other then table
manipulation (eg 'create table','alter table','drop table') then please let
me know so I can extend DBIx::Abstract to include the functionality you are using.

This operation is logged at level 3

=head2 run_delayed

Execute delayed update/insert/delete queries.

This operation is logged at level 5 with the message "Run delayed".

=head2 delete

($table[,$where])

({table=>$table[,where=>$where]})

Deletes records from $table.  See also the documentation on 
L<"DBIx::Abstract Where Clauses">.

=head2 insert

($table,$fields)

({table=>$table,fields=>$fields})

$table is the name of the table to insert into.

$fields is either a reference to a hash of field name/value or
a scalar containg the SQL to insert after the "SET" portion of the statement.

These all produce functionally equivalent SQL.

  $db->insert('foo',{bar=>'baz'});
  $db->insert('foo',q|bar='baz'|);
  $db->insert({table=>'foo',fields=>{bar=>'baz'}});
  $db->insert({table=>'foo',fields=>q|bar='baz'|});
  

=head2 replace

($table,$fields)

({table=>$table,fields=>$fields})

$table is the name of the table to replace into.

$fields is either a reference to a hash of field name/value or
a scalar containg the SQL to insert after the "SET" portion of the statement.

Replace works just like insert, except that if a record with the same
primary key already exists then the existing record is replaced, instead of
producing an error.

=head2 update

($table,$fields[,$where])

({table=>$table,fields=>$fields[,where=>$where]})

$table is the table to update.

$fields is a reference to a hash keyed on field name/new value.

See also the documentation on L<"DBIx::Abstract Where Clauses">.

=head2 select

C<select>

($fields,[$table,[$where[,$order]]])

({fields=>$fields,table=>$table[,where=>$where][,order=>$order][,join=>$join][,group=>$group]})

$fields can be either an array reference or a scalar.  If it is an array
reference then it should be a list of fields to include.  If it is a scalar
then it should be a literal to be inserted into the generated SQL after
"SELECT".

$table can be either an array reference or a scalar. If it is an array
reference then it should be a list of tables to use.  If it is a scalar
then it should be a literal to be inserted into the generated SQL after
"FROM".

See also the documentation on L<"DBIx::Abstract Where Clauses">.

$order is the output order.  If it is a scalar then it is inserted
literally after "ORDER BY".  If it is an arrayref then it is join'd with a
comma and inserted.

$join is there to make joining tables more convenient.  It will takes one or
more (as an arrayref) sets of statements to use when joining.  For instance:

  $dbh->select({
    fields=>'*',
    table=>'foo,bar',
    join=>'foo.id=bar.foo_id',
    where=>{'foo.dollars',['>',30]}
    });

Would produce:

  SELECT * FROM foo,bar WHERE (foo.dollars > ?) and (foo.id=foo_id)

And put 30 into the bind_params list.

$group is/are the field(s) to group by.  It may be scalar or an arrayref. 
If it is a scalar then it should be a literal to be inserted after "GROUP
BY".  If it is an arrayref then it should be a list of fields to group on.

=head2 select_one_to_hashref

($fields,$table[,$where])

({fields=>$fields,table=>$table[,where=>$where]})

This returns a hashref to the first record returned by the select. 
Typically this should be used for cases when your where clause limits you to
one record anyway.

$fields is can be either a array reference or a scalar.  If it is an array
reference then it should be a list of fields to include.  If it is a scalar
then it should be a literal to be inserted into the generated SQL.

$table is the table to select from.

See also the documentation on L<"DBIx::Abstract Where Clauses">.

=head2 select_all_to_hashref

($fields,$table[,$where])

({fields=>$fields,table=>$table[,where=>$where]})

This returns a hashref to all of the results of the select.  It is keyed on
the first field.  If there are only two fields then the value is just the
second field.  If there are more then two fields then the value is set to an
arrayref that contains all of the fields.

$fields is can be either a array reference or a scalar.  If it is an array
reference then it should be a list of fields to include.  If it is a scalar
then it should be a literal to be inserted into the generated SQL.

$table is the table to select from.

See also the documentation on L<"DBIx::Abstract Where Clauses">.

=head2 fetchrow_hashref

This is just a call to the DBI method.

=head2 fetchrow_hash

This calls fetchrow_hashref and deferences it for you.

=head2 fetchrow_array

This method calls the database handle's method of the same name.

=head2 fetchall_arrayref

This method calls the database handle's method of the same name.

=head2 rows

This method calls the database handle's method of the same name.

=head2 quote

This method is passed to the database handle via AUTOLOAD.

=head2 disconnect

This method is passed to the database handle via AUTOLOAD.

=head2 commit

This method is passed to the database handle via AUTOLOAD.

=head2 rollback

This method is passed to the database handle via AUTOLOAD.

=head2 trace

This method is passed to the database handle via AUTOLOAD.

=head2 finish

This method is passed to the statement handle via AUTOLOAD.

=head2 bind_col

This method is passed to the statement handle via AUTOLOAD.

=head2 bind_columns

This method is passed to the statement handle via AUTOLOAD.

=head1 Other things that need explaination

=head2 DBIx::Abstract Where Clauses

Where clauses in DBIx::Abstract can either be very simple, or highly complex.  They
are designed to be easy to use if you are just typing in a hard coded
statement or have to build a complex query from data.

Wheres are either a scalar, hash-ref or array-ref:

If it is a scalar, then it is used as the literal where.

If it is a hash-ref then the key is the field to check,
the value is either a literal value to compare equality to,
or an array-ref to an array of operator and value.

  {
   first=>'joe',
   age=>['>',26],
   last=>['like',q|b'%|]
  }

Would produce:

 WHERE first = ? AND last like ? AND age > ?
 
With joe, b'% and 26 passed as bind values.

If it is an array-ref then it is an array of hash-refs and
connectors:

  [
    {
      first=>'joe',
      age=>['>',26]
    },
    'OR',
    {
      last=>['like',q|b'%|]
    }
  ]

Would produce:

 WHERE (first = ? AND age > ?) OR (last like ?)
 
With joe, 26 and b'% passed as bind values.

  [
    {
      first=>'joe',
      last=>['like','%foo%'],
    },
    'AND',
    [
      {age=>['>',26]},
      'OR',
      {age=>['<',30]}
    ]
  ]

Would produce:
  
  WHERE (first = ? AND last like ?) AND ((age > ?) OR (age < ?))

With joe, %foo%, 26 and 30 passed as bind values.


=back

=over 5

=head1 SUPPORTED DBD DRIVERS

These drivers have been reported to work:

=item * mysql (development environment)

=item * Pg (with a prerelease version of DBIx::Abstract)

=item * XBase

Any driver that uses ODBC syntax should work using the hash ref method. 
With other drivers you should pass the DBI data source instead (this method
will work with all drivers.)

=back

=head1 CHANGE SINCE LAST RELEASE

=over 2

=item * Fixed bug in make test that caused it to fail when a password was
        needed for testing.  This didn't effect me as my database accepts
        anonymous connections to the test database over loopback.

=item * Fixed some warnings when username or password were undefined.


=back

=head1 AUTHOR

Andrew Turner <turnera@cpan.org>

=head1 COPYRIGHT

(C) Copyright 1998-2000 MINT

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 WEBSITE

http://members.mint.net/turner/db/

=head1 SEE ALSO

L<DBI(3)>

=cut