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

plan test => 18;

eval {
    require DBIx::Abstract;
}; ok($@, '', 'loading module');

eval {
    import DBIx::Abstract;
}; ok($@, '', 'running import');

eval {
    $dbh = DBIx::Abstract->connect({
        dsn=>$dsn,user=>$user,pass=>$pass,
    });
}; ok(ref($dbh), 'DBIx::Abstract', 'connect dbname');

eval {
    $dbh->disconnect if $dbh;
    $dbh = DBIx::Abstract->connect({
        dsn=>$dsn,user=>$user,pass=>$pass,
    });
}; ok($@ || ref($dbh), 'DBIx::Abstract', 'connect db');

eval {
    $dbh->opt(loglevel=>5) if $dbh;
    $dbh->opt(logfile=>'test.log') if $dbh;
}; ok($@?0:1,1,'log sql');

eval {
    $dbh->disconnect if $dbh;
    $dbh->reconnect if $dbh;
}; ok((!$@ and $dbh and $dbh->connected)?1:0,1,'reconnect db');

eval {
    $dbh->query('create table foo (id int null,name char(30) not null,value char(30) null)');
    $dbh->query('create table bar (id int null,foo_id int null,name char(30) not null)');
}; ok($@,'','create');

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

eval {
    $dbh->update('foo',{name=>'blat', value=>'bonk'},{id=>2});
}; ok($@,'','update');

eval {
    $dbh->select('*','foo',{id=>['<',10]});
    $dbh->rows;
    while(@foo = $dbh->fetchrow) { $count2 ++ }
}; ok((!$@ and $count1==$count2)?1:0,1,"select ($count1==$count2)");


eval {
    my @foo;
    @foo = ({id=>['<',10]},'and',\@foo);
    $dbh->select('*','foo',\@foo);
    if ($dbh->rows) {
        while(@foo = $dbh->fetchrow) { $count2 ++ }
    }
}; ok($@?1:0,1,'circular where');

eval {
    $dbh->select('*','foo',[{id=>['<',10]},'and',[{name=>'blat'},'or',{value=>'bonk'}]]);
    $dbh->rows;
    while(@foo = $dbh->fetchrow) { $count2 ++ }
}; ok($@,'','select with complex while');

eval {
    $dbh->select({
        fields=>'*',
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

eval {
    $dbh->delete('foo',{id=>['like','%']});
}; ok((!$@ and $count1==$dbh->rows)?1:0,1,'delete');

eval {
    $dbh->query('drop table foo');
    $dbh->query('drop table bar');
}; ok($@,'','drop');

eval { 
    $dbh->connected or die "ARGH!\n";
}; ok($@,'','good connected');

eval { 
    $dbh->disconnect;
}; ok($@,'','disconnect');

eval { 
    $dbh->connected and die "ARGH!\n";
}; ok($@,'','bad connected');
