#!/usr/bin/perl -w

BEGIN {
  if ($] < '5.00405') {
    use lib 'lib';
  }
  eval 'use Test';
  die $@ if $@;
}

my $dsn  = q{~~test_dsn~~};
my $user = q{~~test_user~~} || undef;
my $pass = q{~~test_pass~~} || undef;

plan test => 20;

# 1
eval {
    require DBIx::Abstract;
}; ok($@, '', 'loading module');

# 2
eval {
    import DBIx::Abstract;
}; ok($@, '', 'running import');

# 3
eval {
    $dbh = DBIx::Abstract->connect({
        dsn=>$dsn,user=>$user,password=>$pass,
    });
}; ok(ref($dbh), 'DBIx::Abstract', 'connect dbname');

# 4
eval {
    $dbh->disconnect if $dbh;
    my $dbi = DBI->connect($dsn,$user,$pass);
    $dbh = DBIx::Abstract->connect($dbi);
}; ok(ref($dbh), 'DBIx::Abstract', 'connect with dbi object');

# 5
eval {
    $dbh->disconnect if $dbh;
    $dbh = DBIx::Abstract->connect({
        dsn=>$dsn,user=>$user,password=>$pass,
    },{
      loglevel=>5,
      logfile=>'test.log',
    });
}; ok($@ || ref($dbh), 'DBIx::Abstract', 'connect db');

# 6
eval {
    $dbh->disconnect if $dbh;
    $dbh->reconnect if $dbh;
}; ok((!$@ and $dbh and $dbh->connected)?1:0,1,'reconnect db');

# 7
eval {
    my $dbih = $dbh->{'dbh'};
#    my $dbh2 = DBIx::Abstract->connect($dbih);
#    $dbh2->DESTROY();
}; ok((!$@ and $dbh and $dbh->connected)?1:0,1,'connect w/dbhandle and destroy');

# 8
eval {
    $dbh->query('create table foo (id int null,name char(30) not null,value char(30) null)');
    $dbh->query('create table bar (id int null,foo_id int null,name char(30) not null)');
}; ok($@,'','create');

# 9
eval {
    $dbh->insert('foo',{id=>1,name=>'test',value=>'this'});
    $dbh->insert('foo',{id=>2,name=>'bar',value=>'baz'});
    $dbh->insert('foo',{id=>3,name=>'this',value=>'test'});
    $dbh->insert('foo',{id=>4,name=>'baz',value=>'bar'});
    $dbh->insert('bar',{id=>1,foo_id=>4,name=>'heh'});
    $dbh->insert('bar',{id=>2,foo_id=>3,name=>'heh'});
    $dbh->insert('bar',{id=>3,foo_id=>2,name=>'heh'});
    $dbh->insert('bar',{id=>4,foo_id=>1,name=>'baz'});
    $count1=4;
}; ok($@,'','insert');

# 10
eval {
    $dbh->update('foo',{name=>'blat', value=>'bonk'},{id=>2});
}; ok($@,'','update');

# 11
eval {
    $dbh->select('*','foo',{id=>['<',10]});
    $dbh->rows;
    while(@foo = $dbh->fetchrow) { $count2 ++ }
}; ok((!$@ and $count1==$count2)?1:0,1,"select ($count1==$count2)");


# 12
eval {
    my @foo;
    @foo = ({id=>['<',10]},'and',\@foo);
    $dbh->select('*','foo',\@foo);
    if ($dbh->rows) {
        while(@foo = $dbh->fetchrow) { $count2 ++ }
    }
}; ok($@?1:0,1,'circular where');

# 13
eval {
    $dbh->select('*','foo',[{id=>['<',10]},'and',[{name=>'blat'},'or',{value=>'bonk'}]]);
    $dbh->rows;
    while(@foo = $dbh->fetchrow) { $count2 ++ }
}; ok($@,'','select with complex while');

# 14
eval {
    $dbh->select({
        fields=>'count(foo.id)',
        tables=>'foo,bar',       
        'join'=>[
                 'foo.id = bar.foo_id', 
                 ],
            where=>{'foo.id'=>['<',10]},
            group=>'bar.name',
        });
    if ($dbh->rows) {
        while(@foo = $dbh->fetchrow) { $count2 ++ }
    }
}; ok($@,'','select with join');

# 15
eval {
    $dbh->delete('foo',{id=>['like','%']});
}; ok((!$@ and $count1==$dbh->rows)?1:0,1,'delete');

# 16
eval {
    $dbh->query('drop table foo');
    $dbh->query('drop table bar');
}; ok($@,'','drop');

# 17
eval { 
    $dbh->connected or die "ARGH!\n";
}; ok($@,'','good connected');

# 18
eval {
    $dbh->opt('this_does_not_exist',7);
}; ok($@?1:0,1,'invalid option');

# 19
eval { 
    $dbh->disconnect;
}; ok($@,'','disconnect');

# 20
eval { 
    $dbh->connected and die "ARGH!\n";
}; ok($@,'','bad connected');
